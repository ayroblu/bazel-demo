import CallKit
import Foundation
import Observation
import Log
import UIKit

public nonisolated struct PairRequest: Identifiable, Equatable {
  public let id: UUID
  public let name: String
  let secret: Data
}

public nonisolated enum ConnectCallState: Equatable {
  case idle
  case outgoing(peerId: UUID, callId: UUID)
  case incoming(peerId: UUID, callId: UUID)
  case active(peerId: UUID, callId: UUID)

  public var peerId: UUID? {
    switch self {
    case .idle: nil
    case .outgoing(let peerId, _), .incoming(let peerId, _), .active(let peerId, _): peerId
    }
  }

  public var callId: UUID? {
    switch self {
    case .idle: nil
    case .outgoing(_, let callId), .incoming(_, let callId), .active(_, let callId): callId
    }
  }

  /// Ringing, at either end. The audio transport is brought up during this,
  /// so audio being live does not mean the call is up.
  public var isRinging: Bool {
    switch self {
    case .outgoing, .incoming: true
    case .idle, .active: false
    }
  }
}

/// Owns everything that happens before and around a call: who we are paired
/// with, who is in range, the bluetooth signalling, and the CallKit call. The
/// audio transport stays in the app: this asks for it to be started and is
/// told when it came up.
@Observable public class ConnectManager {
  public static let shared = ConnectManager()

  private let store: PairingStore
  private let link: NearbyLink
  private let callKit = CallKitController()
  private var started = false
  private var timeoutTask: Task<Void, Never>?
  private var pairingTask: Task<Void, Never>?
  /// The secret we offered, kept until the other side accepts the pairing.
  private var offeredPairings: [UUID: Data] = [:]
  private var transportConnected = false
  private var peerAccepted = false

  public private(set) var pairedPeers: [PairedPeer] = []
  public private(set) var nearby: [NearbyPeer] = []
  public private(set) var state: ConnectCallState = .idle
  /// This device's stable identity, which the transport advertises so that a
  /// call reaches the device it was agreed with rather than one that happens
  /// to share its name.
  public var localId: UUID { store.localId }

  public var pendingPairRequest: PairRequest?
  public var statusMessage: String?
  /// Set on the caller when the other device could not ring because a Focus
  /// is on. Calling again within a few minutes often gets through.
  public var silencedPeerName: String?

  /// Asks the app to bring the audio transport up against `peerName`. Only
  /// the caller invites, so the two sides cannot invite each other at once.
  /// Reports the peer's stable identity as well as its name: the transport
  /// matches on the identity, and shows the name.
  public var onStartTransport: ((UUID, String, Bool) -> Void)?
  public var onStopTransport: (() -> Void)?
  public var onAudioActivated: (() -> Void)?
  public var onAudioDeactivated: (() -> Void)?
  public var onMute: ((Bool) -> Void)?

  init(store: PairingStore = PairingStore(), localName: String = UIDevice.current.name) {
    self.store = store
    link = NearbyLink(store: store, localName: localName)
    pairedPeers = store.peers
    link.onMessage = { [weak self] frame in
      self?.handle(frame)
    }
    callKit.onStartOutgoing = { [weak self] callId in
      self?.handleOutgoingStarted(callId: callId)
    }
    callKit.onStartFailed = { [weak self] callId in
      self?.handleStartFailed(callId: callId)
    }
    callKit.onAnswer = { [weak self] callId in
      self?.handleAnswer(callId: callId)
    }
    callKit.onEnd = { [weak self] callId in
      self?.handleLocalEnd(callId: callId)
    }
    callKit.onMute = { [weak self] muted in
      self?.onMute?(muted)
    }
    callKit.onAudioActivated = { [weak self] in
      self?.onAudioActivated?()
    }
    callKit.onAudioDeactivated = { [weak self] in
      self?.onAudioDeactivated?()
    }
    link.onNearbyChanged = { [weak self] peers in
      self?.nearby = peers
    }
  }

  /// Called at launch, including a launch into the background triggered by a
  /// paired device writing to us.
  public func start() {
    guard !started else { return }
    started = true
    link.start()
  }

  /// Scanning is the only expensive part, so it follows the foreground.
  public func setScanning(_ scanning: Bool) {
    link.setScanning(scanning)
  }

  public func isNearby(_ peer: PairedPeer) -> Bool {
    nearby.contains { $0.id == peer.id }
  }

  public func unpairedNearby() -> [NearbyPeer] {
    nearby.filter { store.peer(id: $0.id) == nil }
  }

  // MARK: pairing

  /// The bluetooth connection is held open until the other side answers,
  /// because its reply comes back over that connection.
  public func pair(with peer: NearbyPeer) {
    let secret = ConnectCodec.newSecret()
    offeredPairings[peer.id] = secret
    statusMessage = "Asked \(peer.name) to pair"
    link.hold(peerId: peer.id)
    link.send(.pairRequest(name: link.localName, secret: secret), to: peer.id)
    pairingTask?.cancel()
    pairingTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(60))
      guard !Task.isCancelled, let self else { return }
      self.endPairing(with: peer.id)
    }
  }

  private func endPairing(with peerId: UUID) {
    pairingTask?.cancel()
    pairingTask = nil
    offeredPairings.removeValue(forKey: peerId)
    guard state.peerId != peerId else { return }
    link.release(peerId: peerId)
  }

  public func respondToPairRequest(accept: Bool) {
    guard let request = pendingPairRequest else { return }
    pendingPairRequest = nil
    guard accept else {
      link.send(.pairDecline, to: request.id)
      return
    }
    var peer = PairedPeer(id: request.id, name: request.name, secret: request.secret)
    peer.peripheralId = link.peripheralId(for: request.id)
    store.save(peer)
    pairedPeers = store.peers
    statusMessage = "Paired with \(request.name)"
    link.send(.pairAccept(name: link.localName), to: request.id)
  }

  /// An empty name clears the nickname and falls back to what the device
  /// calls itself.
  public func rename(_ peer: PairedPeer, to nickname: String) {
    guard var stored = store.peer(id: peer.id) else { return }
    let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    stored.nickname = trimmed.isEmpty ? nil : trimmed
    store.save(stored)
    pairedPeers = store.peers
  }

  public func unpair(_ peer: PairedPeer) {
    if state.peerId == peer.id {
      endCall()
    }
    store.remove(id: peer.id)
    pairedPeers = store.peers
  }

  // MARK: calling

  public func call(_ peer: PairedPeer) {
    guard case .idle = state else { return }
    guard link.peripheralId(for: peer.id) != nil else {
      statusMessage = "\(peer.displayName) is not in range"
      return
    }
    // Whatever the last call ended with is no longer the current state.
    statusMessage = nil
    let callId = UUID()
    state = .outgoing(peerId: peer.id, callId: callId)
    link.hold(peerId: peer.id)
    callKit.startOutgoing(callId: callId, name: peer.displayName)
  }

  public func endCall() {
    guard let callId = state.callId else { return }
    callKit.requestEnd(callId: callId)
  }

  /// Muting from our own UI goes through CallKit so the system call UI shows
  /// the same thing.
  public func setMuted(_ muted: Bool) {
    guard let callId = state.callId else { return }
    callKit.requestMute(callId: callId, muted: muted)
  }

  public func transportDidConnect() {
    guard state.callId != nil else { return }
    transportConnected = true
    reportConnectedIfReady()
  }

  /// An outgoing call is only connected once the transport is up *and* the
  /// other side answered, otherwise the caller stops hearing ringing while
  /// the callee is still being rung.
  private func reportConnectedIfReady() {
    guard case .outgoing(let peerId, let callId) = state, transportConnected, peerAccepted else {
      return
    }
    timeoutTask?.cancel()
    timeoutTask = nil
    callKit.reportOutgoingConnected(callId: callId)
    state = .active(peerId: peerId, callId: callId)
  }

  /// The transport dropped on its own, which ends the call even though
  /// bluetooth may still be fine.
  public func transportDidEnd() {
    guard let callId = state.callId else { return }
    log("connect transport ended")
    finish(callId: callId, reason: .remoteEnded)
  }

  // MARK: signalling

  private func handle(_ frame: ConnectFrame) {
    switch frame.message {
    case .pairRequest(let name, let secret):
      guard pendingPairRequest == nil else { return }
      pendingPairRequest = PairRequest(id: frame.senderId, name: name, secret: secret)
    case .pairAccept(let name):
      guard let secret = offeredPairings[frame.senderId] else { return }
      var peer = PairedPeer(id: frame.senderId, name: name, secret: secret)
      peer.peripheralId = link.peripheralId(for: frame.senderId)
      store.save(peer)
      pairedPeers = store.peers
      statusMessage = "Paired with \(name)"
      endPairing(with: frame.senderId)
    case .pairDecline:
      statusMessage = "Pairing declined"
      endPairing(with: frame.senderId)
    case .invite(let callId, let name):
      handleInvite(callId: callId, name: name, from: frame.senderId)
    case .cancel(let callId), .decline(let callId), .busy(let callId):
      guard state.callId == callId else { return }
      finish(callId: callId, reason: .remoteEnded)
    case .silenced(let callId):
      guard state.callId == callId else { return }
      silencedPeerName = store.peer(id: frame.senderId)?.displayName ?? "That device"
      finish(callId: callId, reason: .unanswered)
    case .accept(let callId):
      guard state.callId == callId else { return }
      log("connect peer answered", callId.uuidString)
      peerAccepted = true
      reportConnectedIfReady()
    }
  }

  private func handleInvite(callId: UUID, name: String, from peerId: UUID) {
    guard var peer = store.peer(id: peerId) else { return }
    if peer.name != name {
      peer.name = name
      store.save(peer)
      pairedPeers = store.peers
    }
    guard case .idle = state else {
      link.send(.busy(callId: callId), to: peerId)
      return
    }
    log("connect ringing for", peer.displayName, callId.uuidString)
    state = .incoming(peerId: peerId, callId: callId)
    link.hold(peerId: peerId)
    Task { @MainActor [weak self] in
      guard let self else { return }
      let result = await self.callKit.reportIncoming(callId: callId, name: peer.displayName)
      guard case .reported = result else {
        self.failIncoming(callId: callId, from: peerId, silenced: result == .silenced)
        return
      }
      // Bringing the transport up while it rings means the audio is usually
      // ready by the time the call is answered. It stays silent until CallKit
      // activates the audio session.
      self.onStartTransport?(peer.id, peer.displayName, false)
      self.startRingTimeout(callId: callId, seconds: 35)
    }
  }

  /// The system refused to ring, e.g. a Focus filtered the call. There is no
  /// CallKit call to end, and the caller would otherwise ring until it times
  /// out, so it is told the same way a busy device would.
  private func failIncoming(callId: UUID, from peerId: UUID, silenced: Bool) {
    guard state.callId == callId else { return }
    if silenced {
      statusMessage = "A Focus silenced the last call"
      link.send(.silenced(callId: callId), to: peerId)
    } else {
      link.send(.busy(callId: callId), to: peerId)
    }
    teardown()
  }

  private func handleOutgoingStarted(callId: UUID) {
    guard case .outgoing(let peerId, let current) = state, current == callId,
      let peer = store.peer(id: peerId)
    else { return }
    link.send(.invite(callId: callId, name: link.localName), to: peerId)
    onStartTransport?(peer.id, peer.displayName, true)
    startTimeout(callId: callId, seconds: 25, reason: .unanswered) { manager in
      if case .outgoing = manager.state { return true }
      return false
    }
  }

  /// CallKit refused the call, so there is no call to report as ended.
  private func handleStartFailed(callId: UUID) {
    guard state.callId == callId else { return }
    statusMessage = "Could not start the call"
    teardown()
  }

  private func handleAnswer(callId: UUID) {
    guard case .incoming(let peerId, let current) = state, current == callId,
      let peer = store.peer(id: peerId)
    else { return }
    link.send(.accept(callId: callId), to: peerId)
    onStartTransport?(peer.id, peer.displayName, false)
    state = .active(peerId: peerId, callId: callId)
    startTransportTimeout(callId: callId, seconds: 20)
  }

  /// The user ended it from the CallKit UI or ours. Before an answer this is
  /// a decline on the callee side and a cancel on the caller side.
  private func handleLocalEnd(callId: UUID) {
    guard state.callId == callId, let peerId = state.peerId else { return }
    switch state {
    case .incoming:
      link.send(.decline(callId: callId), to: peerId)
    case .outgoing, .active:
      link.send(.cancel(callId: callId), to: peerId)
    case .idle:
      break
    }
    teardown()
  }

  /// Nobody picked up.
  private func startRingTimeout(callId: UUID, seconds: Int) {
    startTimeout(callId: callId, seconds: seconds, reason: .unanswered) { manager in
      if case .incoming = manager.state { return true }
      return false
    }
  }

  /// The call was answered but the audio transport never came up, which is
  /// the one failure CallKit cannot see for itself.
  private func startTransportTimeout(callId: UUID, seconds: Int) {
    startTimeout(callId: callId, seconds: seconds, reason: .failed) { manager in
      !manager.transportConnected
    }
  }

  private func startTimeout(
    callId: UUID, seconds: Int, reason: CXCallEndedReason,
    shouldFire: @escaping @MainActor (ConnectManager) -> Bool
  ) {
    timeoutTask?.cancel()
    timeoutTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled, let self, self.state.callId == callId, shouldFire(self) else {
        return
      }
      log("connect call timed out", callId.uuidString, reason.rawValue)
      if let peerId = self.state.peerId {
        self.link.send(.cancel(callId: callId), to: peerId)
      }
      self.finish(callId: callId, reason: reason)
    }
  }

  /// Ends a call the user did not end, so CallKit has to be told.
  private func finish(callId: UUID, reason: CXCallEndedReason) {
    guard state.callId == callId else { return }
    statusMessage = endedMessage(reason: reason)
    callKit.reportEnded(callId: callId, reason: reason)
    teardown()
  }

  /// The system call UI disappears on its own, so the lobby is the only place
  /// left to say why a call stopped.
  private func endedMessage(reason: CXCallEndedReason) -> String? {
    let name = state.peerId.flatMap { store.peer(id: $0)?.displayName } ?? "The other device"
    switch (reason, state) {
    case (.unanswered, .outgoing): return "\(name) did not answer"
    case (.unanswered, .incoming): return "Missed call from \(name)"
    case (.failed, _): return "Could not connect to \(name)"
    case (.remoteEnded, .outgoing): return "\(name) declined the call"
    case (.remoteEnded, .incoming): return "\(name) cancelled the call"
    case (.remoteEnded, .active): return "\(name) ended the call"
    default: return nil
    }
  }

  private func teardown() {
    timeoutTask?.cancel()
    timeoutTask = nil
    transportConnected = false
    peerAccepted = false
    if let peerId = state.peerId {
      link.release(peerId: peerId)
    }
    state = .idle
    onStopTransport?()
  }
}

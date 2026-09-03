#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Log
import MultipeerConnectivity

nonisolated let callServiceType = "p2p-audio-call"

nonisolated final class SendableBox<T>: @unchecked Sendable {
  let value: T
  init(_ value: T) {
    self.value = value
  }
}

struct PendingInvite: Identifiable {
  let id = UUID()
  let peer: MCPeerID
  let handler: SendableBox<(Bool, MCSession?) -> Void>
}

private var deviceName: String {
  #if os(macOS)
  Host.current().localizedName ?? ProcessInfo.processInfo.hostName
  #else
  UIDevice.current.name
  #endif
}

class MultipeerManager: ObservableObject {
  let peerId = MCPeerID(displayName: deviceName)
  let session: MCSession
  private let advertiser: MCNearbyServiceAdvertiser
  private let browser: MCNearbyServiceBrowser
  private let delegate = MultipeerDelegate()

  @Published var discoveredPeers: [MCPeerID] = []
  @Published var connectedPeer: MCPeerID?
  @Published var connectingPeer: MCPeerID?
  @Published var pendingInvite: PendingInvite?
  @Published var statusMessage: String?
  @Published var isDiscovering = false
  private var resumeDiscoveryOnForeground = false

  private let sink = AudioStreamSink()
  private var outgoingStream: AudioOutputStream?
  private var incomingStream: AudioInputStream?
  private var streamOpenAttempts = 0
  private var connectedAt: Date?

  init() {
    session = MCSession(peer: peerId, securityIdentity: nil, encryptionPreference: .required)
    advertiser = MCNearbyServiceAdvertiser(
      peer: peerId, discoveryInfo: nil, serviceType: callServiceType)
    browser = MCNearbyServiceBrowser(peer: peerId, serviceType: callServiceType)
    delegate.manager = self
    session.delegate = delegate
    advertiser.delegate = delegate
    browser.delegate = delegate
  }

  var onAudioData: (@Sendable (Data) -> Void)? {
    get { delegate.onAudioData }
    set { delegate.onAudioData = newValue }
  }

  func startDiscovery() {
    log("multipeer start discovery", peerId.displayName, callServiceType)
    advertiser.startAdvertisingPeer()
    browser.startBrowsingForPeers()
    isDiscovering = true
    statusMessage = nil
  }

  func stopDiscovery() {
    guard isDiscovering else { return }
    log("multipeer stop discovery")
    advertiser.stopAdvertisingPeer()
    browser.stopBrowsingForPeers()
    discoveredPeers = []
    isDiscovering = false
  }

  /// Radios should not keep advertising/browsing while backgrounded; an
  /// active call's MCSession is left untouched. Discovery resumes on
  /// foreground only if the user had it running.
  func handleDidEnterBackground() {
    resumeDiscoveryOnForeground = isDiscovering
    stopDiscovery()
  }

  func handleWillEnterForeground() {
    if resumeDiscoveryOnForeground {
      resumeDiscoveryOnForeground = false
      startDiscovery()
    }
  }

  func invite(peer: MCPeerID) {
    if let invite = pendingInvite {
      guard invite.peer == peer else {
        statusMessage = "Answer the incoming call from \(invite.peer.displayName) first."
        return
      }
      respond(invite: invite, accept: true)
      return
    }
    guard connectingPeer == nil else { return }
    log("multipeer invite", peer.displayName)
    connectingPeer = peer
    statusMessage = "Calling \(peer.displayName)…"
    browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
  }

  func respond(invite: PendingInvite, accept: Bool) {
    log("multipeer respond", invite.peer.displayName, accept)
    pendingInvite = nil
    if accept {
      connectingPeer = invite.peer
      statusMessage = "Connecting to \(invite.peer.displayName)…"
    } else {
      statusMessage = "Declined call from \(invite.peer.displayName)"
    }
    invite.handler.value(accept, session)
  }

  func disconnect(statusMessage message: String? = nil) {
    log("multipeer disconnect requested", callStateSummary())
    closeAudioStreams()
    session.disconnect()
    connectedPeer = nil
    connectingPeer = nil
    connectedAt = nil
    statusMessage = message
  }

  func makeSender() -> @Sendable (Data) -> Void {
    let sink = sink
    return { data in
      sink.send(data)
    }
  }

  /// Audio rides an `MCSession` byte stream rather than datagrams: no MTU
  /// chunking, and the reliable channel keeps traffic flowing on the
  /// connection for its whole life. Both peers open their own outgoing
  /// stream, so each direction is independent.
  private func openAudioStream(to peer: MCPeerID) {
    guard connectedPeer == peer else { return }
    streamOpenAttempts += 1
    do {
      let raw = try session.startStream(withName: "audio", toPeer: peer)
      let stream = AudioOutputStream(stream: raw, peerName: peer.displayName)
      stream.setOnClosed { [weak self] reason in
        Task { @MainActor [weak self] in
          self?.handleStreamClosed(reason: reason, peer: peer)
        }
      }
      outgoingStream = stream
      sink.set(stream)
      log("multipeer opened audio stream", peer.displayName, "attempt", streamOpenAttempts)
    } catch {
      log("multipeer failed to open audio stream", peer.displayName, error)
      guard streamOpenAttempts < 5 else { return }
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(1))
        self?.openAudioStream(to: peer)
      }
    }
  }

  func handleIncomingStream(_ stream: InputStream, name: String, from peer: MCPeerID) {
    log("multipeer received audio stream", peer.displayName, name)
    incomingStream?.close()
    let onData = delegate.onAudioData
    let inputStream = AudioInputStream(stream: stream, peerName: peer.displayName) { data in
      onData?(data)
    }
    inputStream.setOnClosed { [weak self] reason in
      Task { @MainActor [weak self] in
        self?.handleStreamClosed(reason: reason, peer: peer)
      }
    }
    incomingStream = inputStream
  }

  /// A stream ending before the session does is the earliest warning that the
  /// link is going away, so it is worth its own log line.
  private func handleStreamClosed(reason: String, peer: MCPeerID) {
    log(
      "multipeer audio stream closed", peer.displayName, reason, "still connected",
      connectedPeer == peer, callStateSummary())
  }

  private func closeAudioStreams() {
    sink.set(nil)
    outgoingStream?.close()
    outgoingStream = nil
    incomingStream?.close()
    incomingStream = nil
    streamOpenAttempts = 0
  }

  /// A one line snapshot of the transport, logged around every event that
  /// could explain a dropped call.
  func callStateSummary() -> String {
    let out = outgoingStream?.stats()
    let input = incomingStream?.stats()
    let now = Date()
    let uptime = connectedAt.map { String(format: "%.0fs", now.timeIntervalSince($0)) } ?? "-"
    let sinceSend = out?.lastSendAt.map { String(format: "%.1fs", now.timeIntervalSince($0)) } ?? "-"
    let sinceReceive =
      input?.lastReceiveAt.map { String(format: "%.1fs", now.timeIntervalSince($0)) } ?? "-"
    return [
      "uptime=\(uptime)",
      "peers=\(session.connectedPeers.count)",
      "out=\(out.map { "\($0.sent / 1024)kB open=\($0.isOpen) dropped=\($0.dropped / 1024)kB" } ?? "none")",
      "in=\(input.map { "\($0.received / 1024)kB open=\($0.isOpen)" } ?? "none")",
      "sinceSend=\(sinceSend)",
      "sinceReceive=\(sinceReceive)",
    ].joined(separator: " ")
  }

  func handleFound(peer: MCPeerID) {
    log("multipeer found peer", peer.displayName)
    if !discoveredPeers.contains(peer) {
      discoveredPeers.append(peer)
    }
  }

  func handleLost(peer: MCPeerID) {
    log("multipeer lost peer", peer.displayName)
    discoveredPeers.removeAll { $0 == peer }
  }

  func handleInvite(from peer: MCPeerID, handler: SendableBox<(Bool, MCSession?) -> Void>) {
    log("multipeer received invite", peer.displayName)
    guard connectedPeer == nil else {
      log("multipeer rejecting invite because already connected", peer.displayName)
      handler.value(false, nil)
      return
    }
    if connectingPeer == peer {
      log("multipeer accepting invite from peer we were already calling", peer.displayName)
      connectingPeer = nil
      statusMessage = "Connecting to \(peer.displayName)…"
      handler.value(true, session)
      return
    }
    guard pendingInvite == nil else {
      log("multipeer rejecting invite because another invite is pending", peer.displayName)
      handler.value(false, nil)
      return
    }
    pendingInvite = PendingInvite(peer: peer, handler: handler)
    statusMessage = "Incoming call from \(peer.displayName)"
  }

  var onCallStarted: (() -> Void)?
  var onCallEnded: (() -> Void)?

  func handleStateChange(peer: MCPeerID, state: MCSessionState) {
    switch state {
    case .connecting:
      connectingPeer = peer
      statusMessage = "Connecting to \(peer.displayName)…"
    case .connected:
      connectingPeer = nil
      connectedPeer = peer
      connectedAt = Date()
      statusMessage = "Connected to \(peer.displayName)"
      // No point advertising/browsing while in a call; search is started
      // manually again after the call ends.
      stopDiscovery()
      openAudioStream(to: peer)
      onCallStarted?()
    case .notConnected:
      let wasConnecting = connectingPeer == peer
      let wasConnected = connectedPeer == peer
      if wasConnected {
        log("multipeer lost connected peer", peer.displayName, callStateSummary())
      }
      closeAudioStreams()
      connectedAt = nil
      if wasConnecting {
        connectingPeer = nil
        statusMessage = "Could not connect to \(peer.displayName). Check permissions and that both apps are open."
      }
      if wasConnected {
        connectedPeer = nil
        statusMessage = "Disconnected from \(peer.displayName)"
        onCallEnded?()
      }
      if !wasConnecting && !wasConnected {
        statusMessage = "Not connected to \(peer.displayName)"
      }
    @unknown default:
      statusMessage = "Unknown connection state for \(peer.displayName)"
    }
  }
}

extension MCSessionState {
  nonisolated var description: String {
    switch self {
    case .notConnected:
      "notConnected"
    case .connecting:
      "connecting"
    case .connected:
      "connected"
    @unknown default:
      "unknown"
    }
  }
}

nonisolated final class MultipeerDelegate: NSObject, MCSessionDelegate,
  MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, @unchecked Sendable
{
  weak var manager: MultipeerManager?
  var onAudioData: (@Sendable (Data) -> Void)?

  func session(_ session: MCSession, peer peerId: MCPeerID, didChange state: MCSessionState) {
    log("multipeer state change", peerId.displayName, state.description, state.rawValue)
    let peer = SendableBox(peerId)
    Task { @MainActor [weak manager] in
      manager?.handleStateChange(peer: peer.value, state: state)
    }
  }

  func session(_ session: MCSession, didReceive data: Data, fromPeer peerId: MCPeerID) {
    log("multipeer unexpected data message", peerId.displayName, data.count)
  }

  func session(
    _ session: MCSession, didReceive stream: InputStream, withName streamName: String,
    fromPeer peerId: MCPeerID
  ) {
    let streamBox = SendableBox(stream)
    let peer = SendableBox(peerId)
    let name = streamName
    Task { @MainActor [weak manager] in
      manager?.handleIncomingStream(streamBox.value, name: name, from: peer.value)
    }
  }

  /// Documented as optional, but leaving it out means the framework picks the
  /// default trust behaviour with no way to see certificate problems in a log.
  func session(
    _ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerId: MCPeerID,
    certificateHandler: @escaping (Bool) -> Void
  ) {
    log("multipeer received certificate", peerId.displayName, certificate?.count ?? 0)
    certificateHandler(true)
  }

  func session(
    _ session: MCSession, didStartReceivingResourceWithName resourceName: String,
    fromPeer peerId: MCPeerID, with progress: Progress
  ) {}

  func session(
    _ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerId: MCPeerID, at localURL: URL?, withError error: Error?
  ) {}

  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerId: MCPeerID,
    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void
  ) {
    let handler = SendableBox(invitationHandler)
    let peer = SendableBox(peerId)
    Task { @MainActor [weak manager] in
      manager?.handleInvite(from: peer.value, handler: handler)
    }
  }

  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error
  ) {
    log("multipeer failed to advertise", error)
  }

  func browser(
    _ browser: MCNearbyServiceBrowser, foundPeer peerId: MCPeerID,
    withDiscoveryInfo info: [String: String]?
  ) {
    let peer = SendableBox(peerId)
    Task { @MainActor [weak manager] in
      manager?.handleFound(peer: peer.value)
    }
  }

  func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerId: MCPeerID) {
    let peer = SendableBox(peerId)
    Task { @MainActor [weak manager] in
      manager?.handleLost(peer: peer.value)
    }
  }

  func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
    log("multipeer failed to browse", error)
  }
}

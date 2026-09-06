import Combine
import Foundation
import Log
import Network

nonisolated let callServiceType = "_p2p-audio-call._tcp"

public nonisolated final class SendableBox<T>: @unchecked Sendable {
  public let value: T
  public init(_ value: T) {
    self.value = value
  }
}

/// A device offering the call service, as published over Bonjour.
public nonisolated struct Peer: Hashable {
  let id: String
  public let name: String
  let endpoint: NWEndpoint

  init(id: String, name: String, endpoint: NWEndpoint) {
    self.id = id
    self.name = name
    self.endpoint = endpoint
  }

  init?(result: NWBrowser.Result) {
    guard case .service(let name, _, _, _) = result.endpoint else { return nil }
    self.id = name
    self.name = name
    self.endpoint = result.endpoint
  }

  /// A peer reached through an accepted connection carries that connection's
  /// endpoint rather than the browsed service, so identity is the name.
  public static func == (lhs: Peer, rhs: Peer) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

/// Carries a paired call's audio, for the peer the bluetooth side has already
/// agreed the call with.
///
/// Peer-to-peer Wi-Fi is the only path when the two devices share no network,
/// so both the listener and the browser opt into it. Discovery is symmetric:
/// every device advertises and browses, and either side can dial. It runs
/// only while a call is being set up, and a connection from anything other
/// than that call's peer is refused.
public class PeerTransport: ObservableObject {
  let localName: String

  @Published public var connectedPeer: Peer?
  @Published var connectingPeer: Peer?
  @Published public var statusMessage: String?

  private var discoveredPeers: [Peer] = []
  private var isDiscovering = false

  private var listener: NWListener?
  private var browser: NWBrowser?
  private var connection: PeerConnection?
  /// Bonjour appends a suffix when two devices publish the same name, so the
  /// name actually registered is the only reliable way to spot ourselves in
  /// our own browse results.
  private var publishedName: String?
  private var autoConnectPeerName: String?
  private var autoConnectInvites = false
  private var connectedAt: Date?

  private let sink = AudioStreamSink()

  public var onAudioData: (@Sendable (Data) -> Void)?
  public var onCallStarted: (() -> Void)?
  public var onCallEnded: (() -> Void)?

  /// The name is what a peer sees, and what the bluetooth side matches a
  /// call against, so it is supplied rather than read from the device here.
  public init(name: String) {
    localName = name
    publishedName = name
  }

  func startDiscovery() {
    log("peer transport start discovery", localName, callServiceType)
    startListener()
    startBrowser()
    isDiscovering = true
    statusMessage = nil
  }

  func stopDiscovery() {
    guard isDiscovering || listener != nil else { return }
    log("peer transport stop discovery")
    listener?.cancel()
    listener = nil
    stopBrowsing()
  }

  /// Browsing is the expensive half. The listener is left up through a call
  /// so that cancelling it cannot disturb the connection it accepted.
  private func stopBrowsing() {
    browser?.cancel()
    browser = nil
    discoveredPeers = []
    isDiscovering = false
  }

  /// Radios should not keep advertising or browsing while backgrounded. A
  /// call that is being answered from the lock screen is setting up in the
  /// background on purpose, and an active call's connection is left alone.
  public func handleDidEnterBackground() {
    guard autoConnectPeerName == nil, connectedPeer == nil else { return }
    stopDiscovery()
  }

  /// Drives discovery for a call that CallKit is already ringing for: the
  /// named peer is dialled or auto accepted without any prompt. Only the
  /// caller dials, so the two sides cannot dial each other at once.
  public func beginAutoConnect(to name: String, invites: Bool) {
    log("peer transport auto connect", name, "invites", invites)
    autoConnectPeerName = name
    autoConnectInvites = invites
    startDiscovery()
    if invites, let peer = discoveredPeers.first(where: isAutoConnectPeer) {
      dial(peer: peer)
    }
  }

  public func cancelAutoConnect() {
    guard autoConnectPeerName != nil else { return }
    autoConnectPeerName = nil
    autoConnectInvites = false
    stopDiscovery()
  }

  /// The bluetooth side truncates names to fit a notification, so the peer we
  /// are looking for may carry a longer version of the same name.
  private func isAutoConnectPeer(_ peer: Peer) -> Bool {
    guard let name = autoConnectPeerName else { return false }
    return peer.name.hasPrefix(name)
  }

  private func dial(peer: Peer) {
    guard connectingPeer == nil, connectedPeer == nil else { return }
    log("peer transport dial", peer.name)
    connectingPeer = peer
    statusMessage = "Calling \(peer.name)…"
    let connection = PeerConnection(endpoint: peer.endpoint, localName: localName)
    attach(connection)
    self.connection = connection
    connection.start()
  }

  public func disconnect(statusMessage message: String? = nil) {
    log("peer transport disconnect requested", callStateSummary())
    sink.set(nil)
    connection?.cancel()
    connection = nil
    connectedPeer = nil
    connectingPeer = nil
    connectedAt = nil
    statusMessage = message
  }

  public func makeSender() -> @Sendable (Data) -> Void {
    let sink = sink
    return { data in
      sink.send(data)
    }
  }

  /// A one line snapshot of the transport, logged around every event that
  /// could explain a dropped call.
  public func callStateSummary() -> String {
    let stats = connection?.stats()
    let now = Date()
    let uptime = connectedAt.map { String(format: "%.0fs", now.timeIntervalSince($0)) } ?? "-"
    let sinceSend = stats?.lastSendAt.map { String(format: "%.1fs", now.timeIntervalSince($0)) } ?? "-"
    let sinceReceive =
      stats?.lastReceiveAt.map { String(format: "%.1fs", now.timeIntervalSince($0)) } ?? "-"
    return [
      "uptime=\(uptime)",
      "peers=\(connectedPeer == nil ? 0 : 1)",
      "out=\(stats.map { "\($0.sent / 1024)kB open=\($0.isOpen) dropped=\($0.dropped / 1024)kB" } ?? "none")",
      "in=\(stats.map { "\($0.received / 1024)kB open=\($0.isOpen)" } ?? "none")",
      "inEvents=\(stats?.receiveEvents ?? 0)",
      "sinceSend=\(sinceSend)",
      "sinceReceive=\(sinceReceive)",
    ].joined(separator: " ")
  }

  private func startListener() {
    guard listener == nil else { return }
    do {
      let listener = try NWListener(using: PeerConnection.parameters())
      listener.service = NWListener.Service(name: localName, type: callServiceType)
      listener.stateUpdateHandler = { state in
        guard case .failed(let error) = state else { return }
        log("peer transport failed to advertise", error)
      }
      listener.serviceRegistrationUpdateHandler = { [weak self] change in
        guard case .add(let endpoint) = change,
          case .service(let name, _, _, _) = endpoint
        else { return }
        let box = SendableBox(name)
        Task { @MainActor [weak self] in
          self?.publishedName = box.value
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        let box = SendableBox(connection)
        Task { @MainActor [weak self] in
          self?.handleIncoming(box.value)
        }
      }
      listener.start(queue: .main)
      self.listener = listener
    } catch {
      log("peer transport failed to listen", error)
      statusMessage = "Could not make this device discoverable"
    }
  }

  private func startBrowser() {
    guard browser == nil else { return }
    let browser = NWBrowser(
      for: .bonjour(type: callServiceType, domain: nil), using: PeerConnection.parameters())
    browser.stateUpdateHandler = { state in
      guard case .failed(let error) = state else { return }
      log("peer transport failed to browse", error)
    }
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      let box = SendableBox(results.compactMap(Peer.init(result:)))
      Task { @MainActor [weak self] in
        self?.handleBrowseResults(box.value)
      }
    }
    browser.start(queue: .main)
    self.browser = browser
  }

  private func handleBrowseResults(_ peers: [Peer]) {
    let others = peers.filter { $0.name != publishedName }
    for peer in others where !discoveredPeers.contains(peer) {
      log("peer transport found peer", peer.name)
    }
    discoveredPeers = others
    guard autoConnectInvites, connection == nil, connectedPeer == nil,
      let target = others.first(where: isAutoConnectPeer)
    else { return }
    dial(peer: target)
  }

  /// An accepted endpoint carries no name, so the connection is started to
  /// read its hello, and only then is it matched against the call being set
  /// up.
  private func handleIncoming(_ incoming: NWConnection) {
    guard connectedPeer == nil else {
      log("peer transport rejecting connection, already in a call")
      incoming.cancel()
      return
    }
    let connection = PeerConnection(
      connection: incoming, localName: localName, greetsOnReady: false)
    attach(connection)
    connection.start()
  }

  private func attach(_ connection: PeerConnection) {
    let box = SendableBox(connection)
    connection.setHandlers(
      onReady: { name in
        Task { @MainActor [weak self] in
          self?.handleHello(name: name, connection: box.value)
        }
      },
      onData: nil,
      onClosed: { reason in
        Task { @MainActor [weak self] in
          self?.handleClosed(reason: reason, connection: box.value)
        }
      })
  }

  private func handleHello(name: String, connection: PeerConnection) {
    let peer = Peer(id: name, name: name, endpoint: connection.endpoint)
    // Our own dial: the hello is the answer, so the call is up.
    if self.connection === connection {
      activate(connection, peer: connectingPeer ?? peer)
      return
    }
    guard connectedPeer == nil, isAutoConnectPeer(peer) || connectingPeer?.name == peer.name else {
      log("peer transport refusing connection from", peer.name)
      connection.cancel()
      return
    }
    log("peer transport accepting", peer.name)
    activate(connection, peer: peer)
    // Tells the caller its call was answered.
    connection.greet()
  }

  private func activate(_ connection: PeerConnection, peer: Peer) {
    // Both sides dialling at once leaves a second connection behind.
    if let existing = self.connection, existing !== connection {
      existing.cancel()
    }
    self.connection = connection
    connectingPeer = nil
    connectedPeer = peer
    connectedAt = Date()
    statusMessage = "Connected to \(peer.name)"
    let onAudioData = onAudioData
    connection.setDataHandler { data in
      onAudioData?(data)
    }
    sink.set(connection)
    // No point browsing while in a call; search is started manually again
    // after the call ends.
    stopBrowsing()
    log("peer transport connected", peer.name)
    onCallStarted?()
  }

  private func handleClosed(reason: String, connection: PeerConnection) {
    guard self.connection === connection else { return }
    self.connection = nil
    sink.set(nil)
    connectedAt = nil
    if let peer = connectedPeer {
      log("peer transport lost connected peer", peer.name, reason, callStateSummary())
      connectedPeer = nil
      statusMessage = "Disconnected from \(peer.name)"
      onCallEnded?()
      return
    }
    if let peer = connectingPeer {
      log("peer transport could not connect", peer.name, reason)
      connectingPeer = nil
      statusMessage =
        "Could not connect to \(peer.name). Check permissions and that both apps are open."
    }
  }
}

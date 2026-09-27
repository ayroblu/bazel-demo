import Foundation
import Log
import Observation
import transport_protocol

public nonisolated final class SendableBox<T>: @unchecked Sendable {
  public let value: T
  public init(_ value: T) {
    self.value = value
  }
}

public nonisolated struct Peer: Hashable {
  let id: String
  public let name: String

  public static func == (lhs: Peer, rhs: Peer) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

@Observable public class PeerTransport {
  private let localIdentity: String
  private let setup: any LinkSetup

  public var connectedPeer: Peer?
  public var statusMessage: String?

  private var call: LinkCall?
  private var connectingPeer: Peer?
  private var connection: PeerConnection?
  private var connectedAt: Date?

  private let sink = AudioStreamSink()
  private var captureDelayProvider: (@Sendable () -> Int)?

  public var onAudioData: (@Sendable (UInt32, Data) -> Void)?
  public var onCallStarted: (() -> Void)?
  public var onCallEnded: (() -> Void)?

  public init(identity: String, setup: any LinkSetup) {
    localIdentity = identity
    self.setup = setup
    setup.onCarrier = { [weak self] carrier, dials in
      self?.handleCarrier(carrier, dials: dials)
    }
  }

  /// Radios should not keep advertising or browsing while backgrounded. A
  /// call that is being answered from the lock screen is setting up in the
  /// background on purpose, and an active call's connection is left alone.
  public func handleDidEnterBackground() {
    guard call == nil, connectedPeer == nil else { return }
    setup.cancel()
  }

  public func beginAutoConnect(_ call: LinkCall) {
    log("peer transport auto connect", call.peerName, call.peerIdentity, "invites", call.invites)
    self.call = call
    statusMessage = nil
    setup.begin(call)
  }

  public func cancelAutoConnect() {
    guard call != nil else { return }
    call = nil
    setup.cancel()
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

  public func networkStats() -> (
    rttMs: Int?, sentBytes: Int, receivedBytes: Int, peerCaptureMs: Int
  )? {
    guard let stats = connection?.stats() else { return nil }
    return (stats.rttMs.map { Int($0.rounded()) }, stats.sent, stats.received, stats.peerCaptureMs)
  }

  public func setCaptureDelayProvider(_ provider: @escaping @Sendable () -> Int) {
    captureDelayProvider = provider
    connection?.setCaptureDelayProvider(provider)
  }

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
      "rtt=\(stats?.rttMs.map { String(format: "%.0fms", $0) } ?? "-")",
    ].joined(separator: " ")
  }

  private func handleCarrier(_ carrier: any DatagramCarrier, dials: Bool) {
    guard connectedPeer == nil else {
      log("peer transport rejecting carrier, already in a call", carrier.carrierDescription)
      carrier.cancel()
      return
    }
    let link = PeerConnection(
      carrier: carrier, localIdentity: localIdentity, greetsOnReady: dials)
    attach(link)
    if dials {
      guard connectingPeer == nil, let call else {
        carrier.cancel()
        return
      }
      let peer = Peer(id: call.peerIdentity, name: call.peerName)
      log("peer transport dial", peer.name, peer.id, carrier.carrierDescription)
      connectingPeer = peer
      statusMessage = "Calling \(peer.name)…"
      connection?.cancel()
      connection = link
    }
    link.start()
  }

  private func attach(_ connection: PeerConnection) {
    connection.setCaptureDelayProvider(captureDelayProvider)
    let box = SendableBox(connection)
    connection.setHandlers(
      onReady: { identity in
        Task { @MainActor [weak self] in
          self?.handleHello(identity: identity, connection: box.value)
        }
      },
      onData: nil,
      onClosed: { reason in
        Task { @MainActor [weak self] in
          self?.handleClosed(reason: reason, connection: box.value)
        }
      })
  }

  private func handleHello(identity: String, connection: PeerConnection) {
    let peer = Peer(id: identity, name: call?.peerName ?? identity)
    // Our own dial: the hello is the answer, so the call is up. The identity
    // is checked even here, because the service could have been republished
    // by another device between browsing and connecting.
    if self.connection === connection {
      guard connectingPeer?.id == identity else {
        log("peer transport dialled", connectingPeer?.id ?? "-", "but reached", identity)
        connection.cancel()
        return
      }
      activate(connection, peer: peer)
      return
    }
    guard connectedPeer == nil, call?.peerIdentity == identity else {
      log("peer transport refusing connection from", identity)
      connection.cancel()
      return
    }
    log("peer transport accepting", peer.name, identity)
    activate(connection, peer: peer)
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
    connection.setDataHandler { seq, data in
      onAudioData?(seq, data)
    }
    sink.set(connection)
    setup.didConnect()
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
      setup.dialFailed()
      statusMessage =
        "Could not connect to \(peer.name). Check permissions and that both apps are open."
    }
  }
}

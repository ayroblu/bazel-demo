import CryptoKit
import Foundation
import Log
import Network
import Security

/// Both ends of a call are copies of this app, so the key that encrypts the
/// audio is baked into it. That hides the call from anything else on the
/// link, but it authenticates nobody: any copy of the app holds the same key.
private nonisolated let presharedKeySeed = "local-call-app.peer-audio.v1"
private nonisolated let presharedKeyIdentity = "local-call-app"

/// One peer-to-peer connection carrying a call's audio in both directions,
/// as DTLS datagrams: audio is late-is-worthless, so a lost packet is never
/// retransmitted and can never stall the packets behind it. Each datagram is
/// one `Packet`; audio carries a sequence number so the receiver can tell a
/// lost packet from a quiet peer.
///
/// Datagrams also mean the hello can be lost, so it repeats until the peer is
/// heard from, and a closed peer is only detectable by silence: pings run for
/// the whole call as keepalive and measure round trip time as a side effect.
nonisolated final class PeerConnection: @unchecked Sendable {
  private let connection: NWConnection
  private let localIdentity: String
  /// The side that dialled greets as soon as the connection is ready. The
  /// side that answered greets only once the user has accepted, so the hello
  /// doubles as the acceptance the caller waits for.
  private let greetsOnReady: Bool
  private let queue = DispatchQueue(label: "call-audio-link", qos: .userInitiated)
  private let lock = NSLock()
  private let epoch = Date()

  private var isOpen = false
  private var didGreet = false
  private var didNotifyClosed = false
  private var sendSeq: UInt32 = 0
  private var bytesSent = 0
  private var bytesDropped = 0
  private var bytesReceived = 0
  private var receiveEvents = 0
  private var lastSendAt: Date?
  private var lastReceiveAt: Date?
  private var loggedDropAt: Date?
  private var peerIdentity: String?
  /// A ping, pong or audio packet proves the peer got our hello.
  private var peerEstablished = false
  private var smoothedRttMs: Double?

  private var helloTimer: DispatchSourceTimer?
  private var pingTimer: DispatchSourceTimer?

  private var onReady: (@Sendable (String) -> Void)?
  private var onClosed: (@Sendable (String) -> Void)?
  private var onData: (@Sendable (UInt32, Data) -> Void)?

  private let receiveTimeout: TimeInterval = 10

  var endpoint: NWEndpoint { connection.endpoint }

  init(connection: NWConnection, localIdentity: String, greetsOnReady: Bool) {
    self.connection = connection
    self.localIdentity = localIdentity
    self.greetsOnReady = greetsOnReady
  }

  convenience init(endpoint: NWEndpoint, localIdentity: String) {
    self.init(
      connection: NWConnection(to: endpoint, using: PeerConnection.parameters()),
      localIdentity: localIdentity, greetsOnReady: true)
  }

  /// Peer-to-peer includes AWDL, which is the only path between two devices
  /// that share no network.
  static func parameters() -> NWParameters {
    let parameters = NWParameters(dtls: tlsOptions(), udp: NWProtocolUDP.Options())
    parameters.includePeerToPeer = true
    return parameters
  }

  private static func tlsOptions() -> NWProtocolTLS.Options {
    let options = NWProtocolTLS.Options()
    let key = Data(SHA256.hash(data: Data(presharedKeySeed.utf8)))
      .withUnsafeBytes { DispatchData(bytes: $0) }
    let identity = Data(presharedKeyIdentity.utf8)
      .withUnsafeBytes { DispatchData(bytes: $0) }
    sec_protocol_options_add_pre_shared_key(
      options.securityProtocolOptions, key as __DispatchData, identity as __DispatchData)
    // A pre-shared key needs a ciphersuite that can be negotiated without a
    // certificate.
    sec_protocol_options_append_tls_ciphersuite(
      options.securityProtocolOptions, tls_ciphersuite_t.AES_128_GCM_SHA256)
    return options
  }

  func setHandlers(
    onReady: (@Sendable (String) -> Void)?,
    onData: (@Sendable (UInt32, Data) -> Void)?,
    onClosed: (@Sendable (String) -> Void)?
  ) {
    lock.lock()
    self.onReady = onReady
    self.onData = onData
    self.onClosed = onClosed
    lock.unlock()
  }

  func setDataHandler(_ handler: (@Sendable (UInt32, Data) -> Void)?) {
    lock.lock()
    onData = handler
    lock.unlock()
  }

  func start() {
    connection.stateUpdateHandler = { [weak self] state in
      self?.handleState(state)
    }
    connection.start(queue: queue)
  }

  /// Handlers are cleared as well as the connection: they capture this object
  /// to keep it alive while it is only referenced by the connection it was
  /// accepted from, so holding them would leak it.
  func cancel() {
    lock.lock()
    didNotifyClosed = true
    isOpen = false
    onReady = nil
    onClosed = nil
    onData = nil
    let timers = [helloTimer, pingTimer]
    helloTimer = nil
    pingTimer = nil
    lock.unlock()
    timers.forEach { $0?.cancel() }
    connection.cancel()
  }

  /// Answering side only: tells the caller the call was accepted.
  func greet() {
    startHello()
  }

  func stats() -> (
    sent: Int, dropped: Int, received: Int, receiveEvents: Int, lastSendAt: Date?,
    lastReceiveAt: Date?, isOpen: Bool, rttMs: Double?
  ) {
    lock.lock()
    defer { lock.unlock() }
    return (
      bytesSent, bytesDropped, bytesReceived, receiveEvents, lastSendAt, lastReceiveAt, isOpen,
      smoothedRttMs
    )
  }

  func rttMs() -> Double? {
    lock.lock()
    defer { lock.unlock() }
    return smoothedRttMs
  }

  /// One encoded audio frame; sequenced and sent as a single datagram, or
  /// dropped on the spot while the connection is not ready: stale audio is
  /// worth less than nothing.
  func send(_ payload: Data) {
    lock.lock()
    guard isOpen else {
      bytesDropped += payload.count
      let shouldLog = shouldLogDropLocked()
      lock.unlock()
      if shouldLog {
        log("peer connection not open, dropping audio")
      }
      return
    }
    let seq = sendSeq
    sendSeq &+= 1
    lock.unlock()
    sendPacket(.audio(seq: seq, payload: payload))
  }

  private func sendPacket(_ packet: Packet) {
    let data = packet.encoded()
    connection.send(
      content: data,
      completion: .contentProcessed { [weak self] error in
        guard let self else { return }
        if let error {
          log("peer connection send failed", error)
          self.notifyClosed("send \(error)")
          return
        }
        self.lock.lock()
        self.bytesSent += data.count
        self.lastSendAt = Date()
        self.lock.unlock()
      })
  }

  private func handleState(_ state: NWConnection.State) {
    switch state {
    case .ready:
      lock.lock()
      isOpen = true
      lock.unlock()
      log("peer connection ready", String(describing: connection.endpoint))
      if greetsOnReady {
        startHello()
      }
      receiveNext()
    case .waiting(let error):
      // Says why the path is not usable yet, which is the only warning
      // before a call fails to come up at all.
      log("peer connection waiting", String(describing: connection.endpoint), error)
    case .failed(let error):
      notifyClosed("failed \(error)")
    case .cancelled:
      notifyClosed("cancelled")
    default:
      break
    }
  }

  /// The hello repeats until the peer is heard from, because any one
  /// datagram can be lost and nothing is retransmitted.
  private func startHello() {
    lock.lock()
    guard !didGreet else {
      lock.unlock()
      return
    }
    didGreet = true
    let timer = DispatchSource.makeTimerSource(queue: queue)
    helloTimer = timer
    lock.unlock()
    timer.schedule(deadline: .now(), repeating: .milliseconds(250))
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      self.lock.lock()
      let done = self.peerIdentity != nil && self.peerEstablished
      self.lock.unlock()
      if done {
        self.stopHello()
        return
      }
      self.sendPacket(.hello(identity: self.localIdentity))
    }
    timer.activate()
    startPingIfEstablished()
  }

  private func stopHello() {
    lock.lock()
    let timer = helloTimer
    helloTimer = nil
    lock.unlock()
    timer?.cancel()
  }

  /// Pings run from both hellos being exchanged until the call ends: the
  /// reply measures round trip time, and going quiet is the only way a dead
  /// peer shows over datagrams, so a silent stretch closes the connection.
  private func startPingIfEstablished() {
    lock.lock()
    guard didGreet, peerIdentity != nil, pingTimer == nil, !didNotifyClosed else {
      lock.unlock()
      return
    }
    let timer = DispatchSource.makeTimerSource(queue: queue)
    pingTimer = timer
    lock.unlock()
    timer.schedule(deadline: .now(), repeating: .seconds(1))
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      self.lock.lock()
      let last = self.lastReceiveAt
      self.lock.unlock()
      if let last, Date().timeIntervalSince(last) > self.receiveTimeout {
        self.notifyClosed("receive timeout")
        return
      }
      self.sendPacket(.ping(sentMs: self.nowMs()))
    }
    timer.activate()
  }

  private func nowMs() -> UInt32 {
    UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince(epoch) * 1000))
  }

  private func receiveNext() {
    connection.receiveMessage { [weak self] data, _, _, error in
      guard let self else { return }
      if let data, !data.isEmpty {
        self.handleReceived(data)
      }
      if let error {
        self.notifyClosed("receive \(error)")
        return
      }
      self.receiveNext()
    }
  }

  private func handleReceived(_ data: Data) {
    lock.lock()
    let isFirst = bytesReceived == 0
    bytesReceived += data.count
    receiveEvents += 1
    lastReceiveAt = Date()
    lock.unlock()
    if isFirst {
      log("peer connection first bytes read", data.count)
    }
    guard let packet = Packet.decode(data) else {
      log("peer connection unreadable datagram", data.count)
      return
    }
    switch packet {
    case .hello(let identity):
      lock.lock()
      let isNew = peerIdentity == nil
      if isNew {
        peerIdentity = identity
      }
      let ready = onReady
      lock.unlock()
      guard isNew else { return }
      log("peer connection hello", identity)
      startPingIfEstablished()
      ready?(identity)
    case .audio(let seq, let payload):
      lock.lock()
      peerEstablished = true
      let handler = onData
      lock.unlock()
      handler?(seq, payload)
    case .ping(let sentMs):
      lock.lock()
      peerEstablished = true
      lock.unlock()
      sendPacket(.pong(echoedMs: sentMs))
    case .pong(let echoedMs):
      let rtt = Double(nowMs() &- echoedMs)
      lock.lock()
      peerEstablished = true
      smoothedRttMs = smoothedRttMs.map { $0 * 0.7 + rtt * 0.3 } ?? rtt
      lock.unlock()
    }
  }

  private func notifyClosed(_ reason: String) {
    lock.lock()
    guard !didNotifyClosed else {
      lock.unlock()
      return
    }
    didNotifyClosed = true
    isOpen = false
    let handler = onClosed
    onReady = nil
    onClosed = nil
    onData = nil
    let timers = [helloTimer, pingTimer]
    helloTimer = nil
    pingTimer = nil
    lock.unlock()
    timers.forEach { $0?.cancel() }
    log("peer connection closed", String(describing: connection.endpoint), reason)
    connection.cancel()
    handler?(reason)
  }

  private func shouldLogDropLocked() -> Bool {
    let now = Date()
    guard let loggedDropAt, now.timeIntervalSince(loggedDropAt) < 5 else {
      self.loggedDropAt = now
      return true
    }
    return false
  }
}

/// The capture thread writes here; the connection behind it is swapped on the
/// main actor as calls come and go.
nonisolated final class AudioStreamSink: @unchecked Sendable {
  private let lock = NSLock()
  private var connection: PeerConnection?

  func set(_ connection: PeerConnection?) {
    lock.lock()
    self.connection = connection
    lock.unlock()
  }

  func send(_ data: Data) {
    lock.lock()
    let connection = connection
    lock.unlock()
    connection?.send(data)
  }
}

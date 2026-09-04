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

/// One peer-to-peer connection carrying a call's audio in both directions.
///
/// The connection opens with a hello frame naming the sender, because an
/// endpoint accepted by a listener carries no service name and the callee
/// would otherwise not know who is calling. Everything after the hello is a
/// raw 16kHz mono Int16 sample run with no framing, so a read is handed on
/// as-is except for a trailing odd byte, which is held back until its pair
/// arrives.
///
/// ```
/// [uint16 big-endian name length][name utf8][samples ...]
/// ```
nonisolated final class PeerConnection: @unchecked Sendable {
  private let connection: NWConnection
  private let localName: String
  /// The side that dialled greets as soon as the connection is ready. The
  /// side that answered greets only once the user has accepted, so the hello
  /// doubles as the acceptance the caller waits for.
  private let greetsOnReady: Bool
  private let queue = DispatchQueue(label: "call-audio-link", qos: .userInitiated)
  private let lock = NSLock()

  private var pending = Data()
  private var isSending = false
  private var isOpen = false
  private var didGreet = false
  private var didNotifyClosed = false
  private var bytesSent = 0
  private var bytesDropped = 0
  private var bytesReceived = 0
  private var receiveEvents = 0
  private var lastSendAt: Date?
  private var lastReceiveAt: Date?
  private var loggedDropAt: Date?
  private var helloBytes: [UInt8] = []
  private var peerName: String?
  private var leftover: UInt8?

  private var onReady: (@Sendable (String) -> Void)?
  private var onClosed: (@Sendable (String) -> Void)?
  private var onData: (@Sendable (Data) -> Void)?

  /// 200ms of 16kHz mono Int16 audio. Anything older than that is stale by
  /// the time it would reach the wire.
  private let maxPendingBytes = 6400
  private let maxNameBytes = 255

  var endpoint: NWEndpoint { connection.endpoint }

  init(connection: NWConnection, localName: String, greetsOnReady: Bool) {
    self.connection = connection
    self.localName = localName
    self.greetsOnReady = greetsOnReady
  }

  convenience init(endpoint: NWEndpoint, localName: String) {
    self.init(
      connection: NWConnection(to: endpoint, using: PeerConnection.parameters()),
      localName: localName, greetsOnReady: true)
  }

  /// Peer-to-peer includes AWDL, which is the only path between two devices
  /// that share no network. Audio is late-is-worthless, so Nagle is off.
  static func parameters() -> NWParameters {
    let tcp = NWProtocolTCP.Options()
    tcp.noDelay = true
    let parameters = NWParameters(tls: tlsOptions(), tcp: tcp)
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
    onData: (@Sendable (Data) -> Void)?,
    onClosed: (@Sendable (String) -> Void)?
  ) {
    lock.lock()
    self.onReady = onReady
    self.onData = onData
    self.onClosed = onClosed
    lock.unlock()
  }

  func setDataHandler(_ handler: (@Sendable (Data) -> Void)?) {
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
    lock.unlock()
    connection.cancel()
  }

  /// Answering side only: tells the caller the call was accepted.
  func greet() {
    queue.async { [weak self] in
      self?.sendHello()
    }
  }

  func stats() -> (
    sent: Int, dropped: Int, received: Int, receiveEvents: Int, lastSendAt: Date?,
    lastReceiveAt: Date?, isOpen: Bool
  ) {
    lock.lock()
    defer { lock.unlock() }
    return (bytesSent, bytesDropped, bytesReceived, receiveEvents, lastSendAt, lastReceiveAt, isOpen)
  }

  func send(_ data: Data) {
    lock.lock()
    pending.append(data)
    var dropped = 0
    if pending.count > maxPendingBytes {
      dropped = pending.count - maxPendingBytes
      pending.removeFirst(dropped)
      bytesDropped += dropped
    }
    let shouldLogDrop = dropped > 0 && shouldLogDropLocked()
    lock.unlock()
    if shouldLogDrop {
      log("peer connection send queue full, dropping", dropped, "bytes")
    }
    queue.async { [weak self] in
      self?.drain()
    }
  }

  private func handleState(_ state: NWConnection.State) {
    switch state {
    case .ready:
      lock.lock()
      isOpen = true
      lock.unlock()
      log("peer connection ready", String(describing: connection.endpoint))
      if greetsOnReady {
        sendHello()
      }
      receiveNext()
      drain()
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

  private func sendHello() {
    lock.lock()
    guard !didGreet else {
      lock.unlock()
      return
    }
    didGreet = true
    lock.unlock()
    let name = Array(localName.utf8.prefix(maxNameBytes))
    var frame = Data([UInt8((name.count >> 8) & 0xff), UInt8(name.count & 0xff)])
    frame.append(contentsOf: name)
    connection.send(
      content: frame,
      completion: .contentProcessed { error in
        guard let error else { return }
        log("peer connection hello failed", error)
      })
  }

  private func drain() {
    lock.lock()
    guard isOpen, !isSending, !pending.isEmpty else {
      lock.unlock()
      return
    }
    let chunk = pending
    pending = Data()
    isSending = true
    let isFirst = bytesSent == 0
    lock.unlock()
    connection.send(
      content: chunk,
      completion: .contentProcessed { [weak self] error in
        guard let self else { return }
        if let error {
          log("peer connection send failed", error)
          self.notifyClosed("send \(error)")
          return
        }
        self.lock.lock()
        self.bytesSent += chunk.count
        self.lastSendAt = Date()
        self.isSending = false
        self.lock.unlock()
        if isFirst {
          log("peer connection first bytes written", chunk.count)
        }
        self.drain()
      })
  }

  private func receiveNext() {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
      [weak self] data, _, isComplete, error in
      guard let self else { return }
      if let data, !data.isEmpty {
        self.handleReceived(data)
      }
      if let error {
        self.notifyClosed("receive \(error)")
        return
      }
      if isComplete {
        self.notifyClosed("ended")
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

    var audio = [UInt8](data)
    var greeting: String?
    if peerName == nil {
      helloBytes.append(contentsOf: audio)
      guard helloBytes.count >= 2 else {
        lock.unlock()
        return
      }
      let length = Int(helloBytes[0]) << 8 | Int(helloBytes[1])
      guard helloBytes.count >= 2 + length else {
        lock.unlock()
        return
      }
      let name = String(decoding: helloBytes[2..<(2 + length)], as: UTF8.self)
      peerName = name
      greeting = name
      audio = Array(helloBytes[(2 + length)...])
      helloBytes = []
    }

    var payload: [UInt8] = []
    if let leftover {
      payload.append(leftover)
      self.leftover = nil
    }
    payload.append(contentsOf: audio)
    if payload.count % 2 == 1 {
      leftover = payload.removeLast()
    }
    let ready = onReady
    let dataHandler = onData
    lock.unlock()

    if isFirst {
      log("peer connection first bytes read", data.count)
    }
    if let greeting {
      log("peer connection hello", greeting)
      ready?(greeting)
    }
    if !payload.isEmpty {
      dataHandler?(Data(payload))
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
    lock.unlock()
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

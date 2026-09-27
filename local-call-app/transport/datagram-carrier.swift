import Foundation
import Log
import Network

/// What a link technology must provide: datagrams in, datagrams out, and
/// open/failed events. `PeerConnection` runs the call protocol on top, so a
/// new carrier gets hello, keepalive, RTT and stats without reimplementing
/// any of it.
nonisolated protocol DatagramCarrier: AnyObject, Sendable {
  var carrierDescription: String { get }
  /// The dialled or accepted network endpoint, for carriers that have one.
  var remoteEndpoint: NWEndpoint? { get }

  /// Must be called before `start`.
  func setHandlers(
    onOpen: @escaping @Sendable () -> Void,
    onDatagram: @escaping @Sendable (Data) -> Void,
    onFailed: @escaping @Sendable (String) -> Void
  )
  func start(queue: DispatchQueue)
  func cancel()
  func send(_ datagram: Data, completion: @escaping @Sendable (Error?) -> Void)
}

/// DTLS datagrams over an `NWConnection`: the AWDL path, and any other
/// interface Network.framework routes to the peer.
nonisolated final class NWDatagramCarrier: DatagramCarrier, @unchecked Sendable {
  private let connection: NWConnection
  private let lock = NSLock()
  private var onOpen: (@Sendable () -> Void)?
  private var onDatagram: (@Sendable (Data) -> Void)?
  private var onFailed: (@Sendable (String) -> Void)?

  init(connection: NWConnection) {
    self.connection = connection
  }

  var carrierDescription: String { String(describing: connection.endpoint) }
  var remoteEndpoint: NWEndpoint? { connection.endpoint }

  func setHandlers(
    onOpen: @escaping @Sendable () -> Void,
    onDatagram: @escaping @Sendable (Data) -> Void,
    onFailed: @escaping @Sendable (String) -> Void
  ) {
    lock.lock()
    self.onOpen = onOpen
    self.onDatagram = onDatagram
    self.onFailed = onFailed
    lock.unlock()
  }

  func start(queue: DispatchQueue) {
    connection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        log("peer connection ready", self.carrierDescription)
        self.handler(\.onOpen)?()
        self.receiveNext()
      case .waiting(let error):
        // Says why the path is not usable yet, which is the only warning
        // before a call fails to come up at all.
        log("peer connection waiting", self.carrierDescription, error)
      case .failed(let error):
        self.handler(\.onFailed)?("failed \(error)")
      case .cancelled:
        self.handler(\.onFailed)?("cancelled")
      default:
        break
      }
    }
    connection.start(queue: queue)
  }

  func cancel() {
    lock.lock()
    onOpen = nil
    onDatagram = nil
    onFailed = nil
    lock.unlock()
    connection.cancel()
  }

  func send(_ datagram: Data, completion: @escaping @Sendable (Error?) -> Void) {
    connection.send(
      content: datagram,
      completion: .contentProcessed { error in
        completion(error)
      })
  }

  private func receiveNext() {
    connection.receiveMessage { [weak self] data, _, _, error in
      guard let self else { return }
      if let data, !data.isEmpty {
        self.handler(\.onDatagram)?(data)
      }
      if let error {
        self.handler(\.onFailed)?("receive \(error)")
        return
      }
      self.receiveNext()
    }
  }

  private func handler<T>(_ path: KeyPath<NWDatagramCarrier, T?>) -> T? {
    lock.lock()
    defer { lock.unlock() }
    return self[keyPath: path]
  }
}

import Foundation
import Log
import Network
import transport_protocol

public nonisolated final class NWDatagramCarrier: DatagramCarrier, @unchecked Sendable {
  private let connection: NWConnection
  private let lock = NSLock()
  private var onOpen: (@Sendable () -> Void)?
  private var onDatagram: (@Sendable (Data) -> Void)?
  private var onFailed: (@Sendable (String) -> Void)?

  public init(connection: NWConnection) {
    self.connection = connection
  }

  public var carrierDescription: String { String(describing: connection.endpoint) }

  public func setHandlers(
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

  public func start(queue: DispatchQueue) {
    connection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        log("peer connection ready", self.carrierDescription)
        self.handler(\.onOpen)?()
        self.receiveNext()
      case .waiting(let error):
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

  public func cancel() {
    lock.lock()
    onOpen = nil
    onDatagram = nil
    onFailed = nil
    lock.unlock()
    connection.cancel()
  }

  public func send(_ datagram: Data, completion: @escaping @Sendable (Error?) -> Void) {
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

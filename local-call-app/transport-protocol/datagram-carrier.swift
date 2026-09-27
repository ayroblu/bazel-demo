import Foundation

public nonisolated protocol DatagramCarrier: AnyObject, Sendable {
  var carrierDescription: String { get }

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

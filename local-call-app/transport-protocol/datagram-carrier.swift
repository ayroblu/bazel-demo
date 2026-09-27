import Foundation

/// What a link technology must provide: datagrams in, datagrams out, and
/// open/failed events. `PeerConnection` runs the call protocol on top, so a
/// new carrier gets hello, keepalive, RTT and stats without reimplementing
/// any of it.
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

public struct ProxyAddress: Sendable, CustomStringConvertible {
  public let host: String
  public let port: UInt16

  public init?(_ text: String) {
    guard let colon = text.lastIndex(of: ":"), colon != text.startIndex,
      let port = UInt16(text[colon...].dropFirst())
    else { return nil }
    host = String(text[..<colon])
    self.port = port
  }

  public var description: String { "\(host):\(port)" }
}

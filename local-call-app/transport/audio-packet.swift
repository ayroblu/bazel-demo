import Foundation

/// One datagram on the call connection.
///
/// ```
/// hello: [0x01][uint16 identity length][identity utf8]
/// audio: [0x02][uint32 seq][opus payload]
/// ping:  [0x03][uint32 sender ms]
/// pong:  [0x04][uint32 echoed sender ms]
/// ```
nonisolated enum Packet: Equatable {
  case hello(identity: String)
  case audio(seq: UInt32, payload: Data)
  case ping(sentMs: UInt32)
  case pong(echoedMs: UInt32)

  func encoded() -> Data {
    switch self {
    case .hello(let identity):
      let bytes = Array(identity.utf8.prefix(255))
      var data = Data([1, UInt8((bytes.count >> 8) & 0xff), UInt8(bytes.count & 0xff)])
      data.append(contentsOf: bytes)
      return data
    case .audio(let seq, let payload):
      var data = Data([2])
      data.append(contentsOf: Self.u32(seq))
      data.append(payload)
      return data
    case .ping(let sentMs):
      return Data([3] + Self.u32(sentMs))
    case .pong(let echoedMs):
      return Data([4] + Self.u32(echoedMs))
    }
  }

  static func decode(_ data: Data) -> Packet? {
    let bytes = [UInt8](data)
    guard let type = bytes.first else { return nil }
    switch type {
    case 1:
      guard bytes.count >= 3 else { return nil }
      let length = Int(bytes[1]) << 8 | Int(bytes[2])
      guard bytes.count >= 3 + length else { return nil }
      return .hello(identity: String(decoding: bytes[3..<(3 + length)], as: UTF8.self))
    case 2:
      guard bytes.count >= 5 else { return nil }
      return .audio(seq: u32(bytes, at: 1), payload: Data(bytes[5...]))
    case 3:
      guard bytes.count >= 5 else { return nil }
      return .ping(sentMs: u32(bytes, at: 1))
    case 4:
      guard bytes.count >= 5 else { return nil }
      return .pong(echoedMs: u32(bytes, at: 1))
    default:
      return nil
    }
  }

  private static func u32(_ value: UInt32) -> [UInt8] {
    [
      UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
      UInt8((value >> 8) & 0xff), UInt8(value & 0xff),
    ]
  }

  private static func u32(_ bytes: [UInt8], at index: Int) -> UInt32 {
    UInt32(bytes[index]) << 24 | UInt32(bytes[index + 1]) << 16
      | UInt32(bytes[index + 2]) << 8 | UInt32(bytes[index + 3])
  }
}

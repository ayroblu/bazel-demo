import CryptoKit
import Foundation

/// The signalling messages exchanged over bluetooth. Everything a call needs
/// before the audio transport exists: pairing, ringing, and the answers to it.
nonisolated enum ConnectMessage: Equatable {
  case pairRequest(name: String, secret: Data)
  case pairAccept(name: String)
  case pairDecline
  case invite(callId: UUID, name: String)
  case cancel(callId: UUID)
  case accept(callId: UUID)
  case decline(callId: UUID)
  case busy(callId: UUID)
  /// The system refused to ring because a Focus is on, which the caller shows
  /// differently to a decline: calling again shortly often gets through.
  case silenced(callId: UUID)

  /// Pairing runs before there is a shared secret, so those two messages are
  /// the only ones accepted unauthenticated.
  var isPairing: Bool {
    switch self {
    case .pairRequest, .pairAccept, .pairDecline: true
    default: false
    }
  }

  var callId: UUID? {
    switch self {
    case .invite(let id, _), .cancel(let id), .accept(let id), .decline(let id), .busy(let id),
      .silenced(let id):
      id
    case .pairRequest, .pairAccept, .pairDecline: nil
    }
  }
}

nonisolated enum ConnectFrameError: Error, Equatable {
  case truncated
  case badVersion
  case badBody
  case unknownSender
  case badSignature
  case expired
  case missingSignature
}

/// A framed message with the sender's app identity in the clear, so the
/// receiver can pick the right secret before verifying anything.
nonisolated struct ConnectFrame: Equatable {
  let senderId: UUID
  let message: ConnectMessage
}

nonisolated enum ConnectCodec {
  static let version: UInt8 = 1
  static let maxSkew: TimeInterval = 60
  static let maxNameBytes = 24
  private static let headerSize = 1 + 16 + 8 + 2
  private static let macSize = 32

  static func seal(
    _ message: ConnectMessage, senderId: UUID, secret: Data?, now: Date = Date()
  ) -> Data {
    var frame = Data()
    frame.append(version)
    frame.append(contentsOf: bytes(of: senderId))
    frame.append(contentsOf: bigEndian(UInt64(now.timeIntervalSince1970 * 1000)))
    let body = encode(message)
    frame.append(contentsOf: bigEndian(UInt16(body.count)))
    frame.append(body)
    guard let secret, !message.isPairing else { return frame }
    let mac = HMAC<SHA256>.authenticationCode(for: frame, using: SymmetricKey(data: secret))
    frame.append(contentsOf: Array(mac))
    return frame
  }

  static func open(
    _ data: Data, now: Date = Date(), secretFor: (UUID) -> Data?
  ) throws -> ConnectFrame {
    let raw = [UInt8](data)
    guard raw.count > headerSize else { throw ConnectFrameError.truncated }
    guard raw[0] == version else { throw ConnectFrameError.badVersion }
    guard let senderId = uuid(from: Array(raw[1..<17])) else { throw ConnectFrameError.truncated }
    let millis = integer(UInt64.self, Array(raw[17..<25]))
    let bodyLength = Int(integer(UInt16.self, Array(raw[25..<27])))
    guard raw.count >= headerSize + bodyLength else { throw ConnectFrameError.truncated }
    let body = Array(raw[headerSize..<(headerSize + bodyLength)])
    guard let message = decode(body) else { throw ConnectFrameError.badBody }

    if message.isPairing {
      return ConnectFrame(senderId: senderId, message: message)
    }
    guard raw.count == headerSize + bodyLength + macSize else {
      throw ConnectFrameError.missingSignature
    }
    guard let secret = secretFor(senderId) else { throw ConnectFrameError.unknownSender }
    let signed = Data(raw[0..<(headerSize + bodyLength)])
    let mac = Data(raw[(headerSize + bodyLength)...])
    guard
      HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: signed, using: SymmetricKey(data: secret))
    else { throw ConnectFrameError.badSignature }
    let sentAt = Date(timeIntervalSince1970: Double(millis) / 1000)
    guard abs(now.timeIntervalSince(sentAt)) <= maxSkew else { throw ConnectFrameError.expired }
    return ConnectFrame(senderId: senderId, message: message)
  }

  /// A name has to survive a bluetooth notify, whose payload can be as small
  /// as 20 bytes on a link that never negotiated a larger MTU.
  static func trimmed(name: String) -> String {
    var trimmed = name
    while trimmed.utf8.count > maxNameBytes {
      trimmed = String(trimmed.dropLast())
    }
    return trimmed
  }

  static func newSecret() -> Data {
    Data(SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) })
  }

  private enum Kind: UInt8 {
    case pairRequest = 1
    case pairAccept = 2
    case pairDecline = 3
    case invite = 4
    case cancel = 5
    case accept = 6
    case decline = 7
    case busy = 8
    case silenced = 9
  }

  private static func encode(_ message: ConnectMessage) -> Data {
    var body = Data()
    switch message {
    case .pairRequest(let name, let secret):
      body.append(Kind.pairRequest.rawValue)
      body.append(block(Data(trimmed(name: name).utf8)))
      body.append(block(secret))
    case .pairAccept(let name):
      body.append(Kind.pairAccept.rawValue)
      body.append(block(Data(trimmed(name: name).utf8)))
    case .pairDecline:
      body.append(Kind.pairDecline.rawValue)
    case .invite(let callId, let name):
      body.append(Kind.invite.rawValue)
      body.append(contentsOf: bytes(of: callId))
      body.append(block(Data(trimmed(name: name).utf8)))
    case .cancel(let callId):
      body.append(Kind.cancel.rawValue)
      body.append(contentsOf: bytes(of: callId))
    case .accept(let callId):
      body.append(Kind.accept.rawValue)
      body.append(contentsOf: bytes(of: callId))
    case .decline(let callId):
      body.append(Kind.decline.rawValue)
      body.append(contentsOf: bytes(of: callId))
    case .busy(let callId):
      body.append(Kind.busy.rawValue)
      body.append(contentsOf: bytes(of: callId))
    case .silenced(let callId):
      body.append(Kind.silenced.rawValue)
      body.append(contentsOf: bytes(of: callId))
    }
    return body
  }

  private static func decode(_ body: [UInt8]) -> ConnectMessage? {
    var reader = Reader(body)
    guard let rawKind = reader.byte(), let kind = Kind(rawValue: rawKind) else { return nil }
    switch kind {
    case .pairRequest:
      guard let name = reader.string(), let secret = reader.block(), secret.count == 32 else {
        return nil
      }
      return .pairRequest(name: name, secret: secret)
    case .pairAccept:
      guard let name = reader.string() else { return nil }
      return .pairAccept(name: name)
    case .pairDecline:
      return .pairDecline
    case .invite:
      guard let callId = reader.uuid(), let name = reader.string() else { return nil }
      return .invite(callId: callId, name: name)
    case .cancel:
      return reader.uuid().map { .cancel(callId: $0) }
    case .accept:
      return reader.uuid().map { .accept(callId: $0) }
    case .decline:
      return reader.uuid().map { .decline(callId: $0) }
    case .busy:
      return reader.uuid().map { .busy(callId: $0) }
    case .silenced:
      return reader.uuid().map { .silenced(callId: $0) }
    }
  }

  private static func block(_ data: Data) -> Data {
    var out = Data(bigEndian(UInt16(data.count)))
    out.append(data)
    return out
  }

  private static func bigEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    withUnsafeBytes(of: value.bigEndian) { Array($0) }
  }

  private static func integer<T: FixedWidthInteger>(_ type: T.Type, _ bytes: [UInt8]) -> T {
    bytes.reduce(T.zero) { ($0 << 8) | T($1) }
  }

  private static func bytes(of id: UUID) -> [UInt8] {
    withUnsafeBytes(of: id.uuid) { Array($0) }
  }

  private static func uuid(from bytes: [UInt8]) -> UUID? {
    guard bytes.count == 16 else { return nil }
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
      ))
  }

  private struct Reader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ bytes: [UInt8]) {
      self.bytes = bytes
    }

    mutating func byte() -> UInt8? {
      guard offset < bytes.count else { return nil }
      defer { offset += 1 }
      return bytes[offset]
    }

    mutating func take(_ count: Int) -> [UInt8]? {
      guard count >= 0, offset + count <= bytes.count else { return nil }
      defer { offset += count }
      return Array(bytes[offset..<(offset + count)])
    }

    mutating func uuid() -> UUID? {
      take(16).flatMap { ConnectCodec.uuid(from: $0) }
    }

    mutating func block() -> Data? {
      guard let length = take(2) else { return nil }
      return take(Int(ConnectCodec.integer(UInt16.self, length))).map { Data($0) }
    }

    mutating func string() -> String? {
      block().flatMap { String(data: $0, encoding: .utf8) }
    }
  }
}

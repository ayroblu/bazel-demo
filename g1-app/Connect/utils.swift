import Foundation
import zlib

extension UInt32 {
  func bytes() -> [UInt8] {
    let value = self
    // Big endian
    return [
      UInt8((value >> 24) & 0xFF),
      UInt8((value >> 16) & 0xFF),
      UInt8((value >> 8) & 0xFF),
      UInt8(value & 0xFF),
    ]
  }
}
extension Data {
  func chunk(into size: Int) -> [Data] {
    stride(from: 0, to: count, by: size).map { index in
      self.subdata(in: index..<(Swift.min(index + size, count)))
    }
  }
  func toCrc32() -> UInt32 {
    let data = self
    let checksum = data.withUnsafeBytes {
      crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))
    }
    return UInt32(checksum)
  }
}

extension Data {
  var hex: String {
    return trimEnd().reduce("0x") { $0 + String(format: "%02x", $1) }
  }
  func trimEnd() -> Data {
    let data = self
    var lastNonZero = data.count - 1
    while lastNonZero >= 0 && data[lastNonZero] == 0 {
      lastNonZero -= 1
    }
    if lastNonZero < 0 {
      return Data()
    }
    return data[0...lastNonZero]
  }
  func ascii() -> String? {
    return String(data: self.trimEnd(), encoding: .ascii)
  }
}
extension String {
  func trimEnd() -> String {
    return self.replacingOccurrences(
      of: "\\s+$", with: "", options: .regularExpression)
  }
  func trim() -> String {
    return self.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

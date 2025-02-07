import Foundation
import Log
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

extension UInt8 {
  var hex: String {
    return String(format: "0x%02X", self)
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

func toJson(dict: Any) -> Data? {
  let jsonData = try? JSONSerialization.data(withJSONObject: dict)
  guard let jsonData = jsonData else {
    log("invalid json:", dict)
    return nil
  }
  guard let json = String(data: jsonData, encoding: .utf8)?.data(using: .utf8) else {
    log("invalid data -> string:", dict)
    return nil
  }
  return json
}

struct Info {
  static let id: String = Bundle.main.bundleIdentifier ?? ""
  static let name: String = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? ""
  // static let name: String = "Bazel App"
}

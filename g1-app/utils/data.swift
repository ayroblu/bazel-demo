import Foundation
import zlib

extension UInt32 {
  public func bytes() -> [UInt8] {
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
extension Bool {
  public func uint8() -> UInt8 {
    return self ? 1 : 0
  }
}
extension Array where Element: Any {
  func splat() -> (Element, Element) {
    return (self[0], self[1])
  }
  public func chunk(into size: Int) -> [ArraySlice<Element>] {
    stride(from: 0, to: count, by: size).map { index in
      self[index..<(Swift.min(index + size, count))]
    }
  }
}
extension Array where Element == UInt8 {
  public func runLengthEncode() -> [Element] {
    let input = self
    guard !input.isEmpty else { return [] }

    var result: [UInt8] = []
    var currentByte = input[0]
    var count: UInt8 = 1

    for i in 1..<input.count {
      if input[i] == currentByte && count < 255 {
        count += 1
      } else {
        result.append(count)
        result.append(currentByte)

        currentByte = input[i]
        count = 1
      }
    }

    result.append(count)
    result.append(currentByte)

    return result
  }

  public func runLengthDecode() -> [Element] {
    return self.chunk(into: 2).flatMap { chunk in
      let (len, code) = Array(chunk).splat()
      return [UInt8](repeating: code, count: Int(len))
    }
  }
}
extension Data {
  public func chunk(into size: Int) -> [Data] {
    stride(from: 0, to: count, by: size).map { index in
      self.subdata(in: index..<(Swift.min(index + size, count)))
    }
  }
  public func toCrc32() -> UInt32 {
    let data = self
    let checksum = data.withUnsafeBytes {
      crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))
    }
    return UInt32(checksum)
  }
}

extension UInt8 {
  public var hex: String {
    return String(format: "0x%02X", self)
  }
}
extension Data {
  public var hex: String {
    return trimEnd().reduce("0x") { $0 + String(format: "%02x", $1) }
  }
  public var hexSpace: String {
    return trimEnd().reduce("0x") { $0 + String(format: "%02x ", $1) }
  }
  public func trimEnd() -> Data {
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
  public func ascii() -> String? {
    return String(data: self.trimEnd(), encoding: .ascii)
  }
}
extension String {
  public func trimEnd() -> String {
    return self.replacingOccurrences(
      of: "\\s+$", with: "", options: .regularExpression)
  }
  public func trim() -> String {
    return self.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  public func uint8() -> [UInt8] {
    return [UInt8](self.data(using: .utf8)!)
  }
  public func data() -> Data {
    return self.data(using: .utf8)!
  }
}

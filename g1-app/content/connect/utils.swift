import Foundation
import Log

extension Array where Element == Bool {
  /// Encodes an array of bools as bytes (little endian)
  /// e.g. [true, false, false, false, false, false, false, false] is [1]
  func toBytes() -> [UInt8] {
    return self.chunk(into: 8).map {
      (chunk: ArraySlice<Bool>) -> UInt8 in
      var byte: UInt8 = 0
      for (i, show) in chunk.enumerated() {
        byte |= show.uint8() << i
      }
      return byte
    }
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

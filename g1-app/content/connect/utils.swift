import Foundation
import Log

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

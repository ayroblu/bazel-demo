import Foundation

extension URL {
  public static func / (url: URL, path: String) -> URL {
    return url.appendingPathComponent(path)
  }
}
extension FileManager {
  public func fileExists(atUrl url: URL) -> Bool {
    return fileExists(atPath: url.path)
  }
  public func dirExists(atUrl url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
  }
}

public func mkdirp(_ url: URL) throws {
  let fileManager = FileManager.default
  if !fileManager.fileExists(atPath: url.path) {
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
  }
}
public func rm(_ url: URL) throws {
  let fileManager = FileManager.default
  if fileManager.fileExists(atPath: url.path) {
    try fileManager.removeItem(at: url)
  }
}

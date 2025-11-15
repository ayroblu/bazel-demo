import Foundation

extension URL {
  public static func / (url: URL, path: String) -> URL {
    return url.appendingPathComponent(path)
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

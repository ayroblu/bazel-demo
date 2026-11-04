import CoreServices
import Foundation
import Yams

public final class ConfigFile<Value: Codable> {
  public private(set) var url: URL
  private var knownModificationDate: Date?

  public init(folder: URL, name: String) {
    url = folder.appending(path: name)
  }

  public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

  public var hasChanged: Bool { modificationDate() != knownModificationDate }

  public func load() -> Value? {
    knownModificationDate = modificationDate()
    return (try? String(contentsOf: url, encoding: .utf8)).flatMap {
      try? YAMLDecoder().decode(Value.self, from: $0)
    }
  }

  public func save(_ value: Value) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encodeYAML(value).write(to: url, atomically: true, encoding: .utf8)
    knownModificationDate = modificationDate()
  }

  public func move(to folder: URL) throws {
    let destination = folder.appending(path: url.lastPathComponent)
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    if exists, !fileManager.fileExists(atPath: destination.path) {
      try fileManager.moveItem(at: url, to: destination)
    }
    url = destination
    knownModificationDate = nil
  }

  private func modificationDate() -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
  }
}

public final class FolderWatcher {
  private let onChange: () -> Void
  private var stream: FSEventStreamRef?

  public init(onChange: @escaping () -> Void) {
    self.onChange = onChange
  }

  public func watch(_ folder: URL) {
    if let stream {
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
    }
    var context = FSEventStreamContext(
      version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
      copyDescription: nil)
    stream = FSEventStreamCreate(
      nil, handleFolderEvents, &context, [folder.resolvingSymlinksInPath().path] as CFArray,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
      FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))
    guard let stream else { return }
    FSEventStreamSetDispatchQueue(stream, .main)
    FSEventStreamStart(stream)
  }

  fileprivate func fire() {
    onChange()
  }
}

private func encodeYAML(_ value: some Encodable) throws -> String {
  let encoder = YAMLEncoder()
  encoder.options.allowUnicode = true
  encoder.options.sortKeys = true
  encoder.options.width = -1
  encoder.options.newLineScalarStyle = .literal
  return try encoder.encode(value)
}

private nonisolated func handleFolderEvents(
  _ stream: ConstFSEventStreamRef, _ info: UnsafeMutableRawPointer?, _ count: Int,
  _ paths: UnsafeMutableRawPointer, _ flags: UnsafePointer<FSEventStreamEventFlags>,
  _ ids: UnsafePointer<FSEventStreamEventId>
) {
  guard let info else { return }
  let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
  MainActor.assumeIsolated { watcher.fire() }
}

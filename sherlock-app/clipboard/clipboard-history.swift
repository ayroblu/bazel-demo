import AppKit
import CryptoKit

public nonisolated struct ClipboardEntry: Codable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case text
    case richText
    case image
    case files
  }

  public let id: UUID
  public let kind: Kind
  public let text: String
  public let date: Date
  public let sourceAppPath: String?
  public let imageWidth: Int?
  public let imageHeight: Int?
  let fingerprint: String
  let storedTypes: [String]

  public var filePaths: [String] {
    kind == .files ? text.split(separator: "\n").map(String.init) : []
  }
}

nonisolated extension ClipboardEntry {
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    text = try container.decode(String.self, forKey: .text)
    date = try container.decode(Date.self, forKey: .date)
    sourceAppPath = try container.decodeIfPresent(String.self, forKey: .sourceAppPath)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .text
    imageWidth = try container.decodeIfPresent(Int.self, forKey: .imageWidth)
    imageHeight = try container.decodeIfPresent(Int.self, forKey: .imageHeight)
    fingerprint =
      try container.decodeIfPresent(String.self, forKey: .fingerprint)
      ?? contentFingerprint(text: text, blobs: [:])
    storedTypes = try container.decodeIfPresent([String].self, forKey: .storedTypes) ?? []
  }
}

public final class ClipboardHistory {
  public private(set) var entries: [ClipboardEntry] = []
  private var retention: TimeInterval = 7 * 24 * 60 * 60
  private var changeCount = -1
  private var timer: Timer?

  public init() {
    entries = (try? Data(contentsOf: historyURL)).flatMap {
      try? JSONDecoder().decode([ClipboardEntry].self, from: $0)
    } ?? []
  }

  public func configure(enabled: Bool, retentionDays: Int) {
    retention = TimeInterval(retentionDays) * 24 * 60 * 60
    if enabled, timer == nil {
      changeCount = -1
      let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.poll() }
      }
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    } else if !enabled {
      timer?.invalidate()
      timer = nil
    }
    prune()
  }

  public func clear() {
    entries = []
    prune()
  }

  public func imagePath(of entry: ClipboardEntry) -> String? {
    entry.storedTypes.contains(pngType.rawValue) ? blobURL(entry.id, pngType.rawValue).path : nil
  }

  public func copyToPasteboard(_ entry: ClipboardEntry) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    if entry.kind == .files {
      pasteboard.writeObjects(entry.filePaths.map { URL(fileURLWithPath: $0) as NSURL })
      return
    }
    let item = NSPasteboardItem()
    for type in entry.storedTypes {
      if let data = try? Data(contentsOf: blobURL(entry.id, type)) {
        item.setData(data, forType: NSPasteboard.PasteboardType(type))
      }
    }
    if !entry.text.isEmpty {
      item.setString(entry.text, forType: .string)
    }
    pasteboard.writeObjects([item])
  }

  private func poll() {
    let pasteboard = NSPasteboard.general
    guard pasteboard.changeCount != changeCount else { return }
    changeCount = pasteboard.changeCount
    guard Set(pasteboard.types ?? []).isDisjoint(with: ignoredTypes),
      let (entry, blobs) = capture(pasteboard)
    else { return }
    for old in entries where old.fingerprint == entry.fingerprint {
      try? FileManager.default.removeItem(at: blobFolder(old.id))
    }
    entries.removeAll { $0.fingerprint == entry.fingerprint }
    if !blobs.isEmpty {
      try? FileManager.default.createDirectory(
        at: blobFolder(entry.id), withIntermediateDirectories: true)
      for (type, data) in blobs {
        try? data.write(to: blobURL(entry.id, type))
      }
    }
    entries.insert(entry, at: 0)
    prune()
  }

  private func prune() {
    let cutoff = Date().addingTimeInterval(-retention)
    var images = 0
    entries = Array(
      entries.prefix { $0.date > cutoff }.filter { entry in
        guard entry.kind == .image else { return true }
        images += 1
        return images <= maxImages
      }.prefix(maxEntries))
    removeUnusedBlobs()
    save()
  }

  private func removeUnusedBlobs() {
    let kept = Set(entries.map(\.id.uuidString))
    let folders = (try? FileManager.default.contentsOfDirectory(atPath: blobsURL.path)) ?? []
    for folder in folders where !kept.contains(folder) {
      try? FileManager.default.removeItem(at: blobsURL.appending(path: folder))
    }
  }

  private func save() {
    try? FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: historyURL.deletingLastPathComponent().path)
    try? JSONEncoder().encode(entries).write(to: historyURL, options: [.atomic])
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
  }
}

let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

private let historyURL = URL.applicationSupportDirectory.appending(path: "Sherlock/clipboard.json")

private let blobsURL = URL.applicationSupportDirectory.appending(path: "Sherlock/Clipboard")

private let ignoredTypes: Set<NSPasteboard.PasteboardType> = [
  transientType, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
  NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"),
  NSPasteboard.PasteboardType("com.agilebits.onepassword"),
  NSPasteboard.PasteboardType("de.petermaurer.TransientPasteboardType"),
]

private let pngType = NSPasteboard.PasteboardType.png

private let richTypes: [NSPasteboard.PasteboardType] = [.rtfd, .rtf, .html]

private let maxEntries = 500

private let maxImages = 100

private let maxBlobBytes = 20_000_000

private func blobFolder(_ id: UUID) -> URL {
  blobsURL.appending(path: id.uuidString)
}

private func blobURL(_ id: UUID, _ type: String) -> URL {
  blobFolder(id).appending(path: type)
}

private func capture(_ pasteboard: NSPasteboard) -> (ClipboardEntry, [String: Data])? {
  let source = NSWorkspace.shared.frontmostApplication?.bundleURL?.path
  let files =
    pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    as? [URL] ?? []
  if !files.isEmpty {
    let text = files.map(\.path).joined(separator: "\n")
    let entry = ClipboardEntry(
      id: UUID(), kind: .files, text: text, date: Date(), sourceAppPath: source, imageWidth: nil,
      imageHeight: nil, fingerprint: "files:" + text, storedTypes: [])
    return (entry, [:])
  }
  guard let item = pasteboard.pasteboardItems?.first else { return nil }
  let text = item.string(forType: .string) ?? ""
  let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  var blobs: [String: Data] = [:]
  for type in richTypes {
    if let data = item.data(forType: type), data.count <= maxBlobBytes {
      blobs[type.rawValue] = data
    }
  }
  let image = imageRepresentation(item)
  if let image, image.png.count <= maxBlobBytes {
    blobs[pngType.rawValue] = image.png
  }
  let kind: ClipboardEntry.Kind
  if hasText {
    kind = blobs.keys.contains { $0 != pngType.rawValue } ? .richText : .text
  } else if blobs[pngType.rawValue] != nil {
    kind = .image
  } else {
    return nil
  }
  let entry = ClipboardEntry(
    id: UUID(), kind: kind, text: text, date: Date(), sourceAppPath: source,
    imageWidth: image?.width, imageHeight: image?.height,
    fingerprint: contentFingerprint(text: text, blobs: blobs), storedTypes: blobs.keys.sorted())
  return (entry, blobs)
}

private nonisolated func contentFingerprint(text: String, blobs: [String: Data]) -> String {
  var hash = SHA256()
  hash.update(data: Data(text.utf8))
  for type in blobs.keys.sorted() {
    hash.update(data: blobs[type]!)
  }
  return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

private func imageRepresentation(_ item: NSPasteboardItem) -> (png: Data, width: Int, height: Int)? {
  if let png = item.data(forType: .png), let rep = NSBitmapImageRep(data: png) {
    return (png, rep.pixelsWide, rep.pixelsHigh)
  }
  guard let tiff = item.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
  else { return nil }
  return (png, rep.pixelsWide, rep.pixelsHigh)
}

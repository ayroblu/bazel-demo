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

public final class ClipboardHistory {
  public private(set) var entries: [ClipboardEntry] = []
  private var retention: TimeInterval = 7 * 24 * 60 * 60
  private var changeCount = -1
  private var timer: Timer?
  private var capturing: Task<Void, Never>?

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

  public func richText(of entry: ClipboardEntry) -> NSAttributedString? {
    for type in [NSPasteboard.PasteboardType.rtfd, .rtf]
    where entry.storedTypes.contains(type.rawValue) {
      guard let data = try? Data(contentsOf: blobURL(entry.id, type.rawValue)),
        data.count <= maxRichPreviewBytes
      else { continue }
      let text =
        type == .rtfd
        ? NSAttributedString(rtfd: data, documentAttributes: nil)
        : NSAttributedString(rtf: data, documentAttributes: nil)
      if let text { return text }
    }
    return nil
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
      let copy = readCopy(pasteboard)
    else { return }
    let previous = capturing
    capturing = Task {
      await previous?.value
      guard let entry = await storeCopy(copy) else { return }
      entries.removeAll { $0.fingerprint == entry.fingerprint }
      entries.insert(entry, at: 0)
      prune()
    }
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

private nonisolated let blobsURL = URL.applicationSupportDirectory.appending(path: "Sherlock/Clipboard")

private let ignoredTypes: Set<NSPasteboard.PasteboardType> = [
  transientType, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
  NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"),
  NSPasteboard.PasteboardType("com.agilebits.onepassword"),
  NSPasteboard.PasteboardType("de.petermaurer.TransientPasteboardType"),
]

private nonisolated let pngType = NSPasteboard.PasteboardType.png

private nonisolated let richTypes: [NSPasteboard.PasteboardType] = [.rtfd, .rtf, .html]

private let maxEntries = 500

private let maxImages = 100

private nonisolated let maxBlobBytes = 20_000_000

private let maxRichPreviewBytes = 2_000_000

private nonisolated func blobFolder(_ id: UUID) -> URL {
  blobsURL.appending(path: id.uuidString)
}

private nonisolated func blobURL(_ id: UUID, _ type: String) -> URL {
  blobFolder(id).appending(path: type)
}

private nonisolated struct Copy: Sendable {
  let date: Date
  let sourceAppPath: String?
  let files: [String]
  let text: String
  let formats: [String: Data]
  let png: Data?
  let tiff: Data?
}

private func readCopy(_ pasteboard: NSPasteboard) -> Copy? {
  let files =
    pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    as? [URL] ?? []
  let item = pasteboard.pasteboardItems?.first
  guard !files.isEmpty || item != nil else { return nil }
  var formats: [String: Data] = [:]
  for type in richTypes {
    if let data = item?.data(forType: type), data.count <= maxBlobBytes {
      formats[type.rawValue] = data
    }
  }
  let png = item?.data(forType: .png)
  return Copy(
    date: Date(), sourceAppPath: NSWorkspace.shared.frontmostApplication?.bundleURL?.path,
    files: files.map(\.path), text: item?.string(forType: .string) ?? "", formats: formats,
    png: png, tiff: png == nil ? item?.data(forType: .tiff) : nil)
}

@concurrent private func storeCopy(_ copy: Copy) async -> ClipboardEntry? {
  if !copy.files.isEmpty {
    let text = copy.files.joined(separator: "\n")
    return ClipboardEntry(
      id: UUID(), kind: .files, text: text, date: copy.date, sourceAppPath: copy.sourceAppPath,
      imageWidth: nil, imageHeight: nil, fingerprint: "files:" + text, storedTypes: [])
  }
  var blobs = copy.formats
  let image = imageRepresentation(png: copy.png, tiff: copy.tiff)
  if let image, image.png.count <= maxBlobBytes {
    blobs[pngType.rawValue] = image.png
  }
  let kind: ClipboardEntry.Kind
  if !copy.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    kind = copy.formats.isEmpty ? .text : .richText
  } else if blobs[pngType.rawValue] != nil {
    kind = .image
  } else {
    return nil
  }
  let id = UUID()
  if !blobs.isEmpty {
    try? FileManager.default.createDirectory(at: blobFolder(id), withIntermediateDirectories: true)
    for (type, data) in blobs {
      try? data.write(to: blobURL(id, type))
    }
  }
  return ClipboardEntry(
    id: id, kind: kind, text: copy.text, date: copy.date, sourceAppPath: copy.sourceAppPath,
    imageWidth: image?.width, imageHeight: image?.height,
    fingerprint: contentFingerprint(text: copy.text, blobs: blobs),
    storedTypes: blobs.keys.sorted())
}

private nonisolated func imageRepresentation(png: Data?, tiff: Data?) -> (
  png: Data, width: Int, height: Int
)? {
  if let png, let rep = NSBitmapImageRep(data: png) {
    return (png, rep.pixelsWide, rep.pixelsHigh)
  }
  guard let tiff, let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
  else { return nil }
  return (png, rep.pixelsWide, rep.pixelsHigh)
}

private nonisolated func contentFingerprint(text: String, blobs: [String: Data]) -> String {
  var hash = SHA256()
  hash.update(data: Data(text.utf8))
  for type in blobs.keys.sorted() {
    hash.update(data: blobs[type]!)
  }
  return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

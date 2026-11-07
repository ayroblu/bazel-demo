import AppKit
import Quartz
import clipboard
import search

final class PreviewView: NSView {
  private let textScroll = NSTextView.scrollableTextView()
  private let imageView = NSImageView()
  private let details = NSTextField(wrappingLabelWithString: "")
  private var quickLook: QLPreviewView?
  private var shownKey: String?

  override var isFlipped: Bool { true }

  private var textView: NSTextView { textScroll.documentView as! NSTextView }

  private var contentFrame: NSRect {
    NSRect(x: 4, y: 4, width: bounds.width - 8, height: bounds.height - detailsHeight - 12)
  }

  init(size: NSSize) {
    super.init(frame: NSRect(origin: .zero, size: size))
    textScroll.drawsBackground = false
    textScroll.autohidesScrollers = true
    textScroll.frame = contentFrame
    textView.isEditable = false
    textView.isSelectable = false
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 6, height: 6)
    imageView.imageScaling = .scaleProportionallyDown
    imageView.frame = contentFrame.insetBy(dx: 6, dy: 6)
    details.font = .systemFont(ofSize: 12)
    details.textColor = .secondaryLabelColor
    details.maximumNumberOfLines = 2
    details.lineBreakMode = .byTruncatingMiddle
    details.frame = NSRect(
      x: 12, y: bounds.height - detailsHeight - 6, width: bounds.width - 24, height: detailsHeight)
    for view in [textScroll, imageView, details] {
      addSubview(view)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  func show(_ preview: ResultItem.Preview, clipboard: ClipboardHistory) {
    let key = previewKey(preview)
    guard key != shownKey else { return }
    shownKey = key
    switch preview {
    case .clipboard(let entry):
      showClipboard(entry, clipboard: clipboard)
    case .snippet(let snippet):
      showText(plainText(snippet.text))
      details.stringValue = [
        snippet.keyword.isEmpty ? "No keyword" : "Keyword \(snippet.keyword)",
        characterCount(snippet.text),
      ].joined(separator: " · ")
    case .file(let url):
      showFile(url)
      details.stringValue = fileDetails(url)
    }
  }

  func scroll(by pages: Int) {
    guard !textScroll.isHidden else { return }
    let clip = textScroll.contentView
    let maxY = max(textView.frame.height - clip.bounds.height, 0)
    let y = min(max(clip.bounds.origin.y + CGFloat(pages) * clip.bounds.height * 0.8, 0), maxY)
    clip.scroll(to: NSPoint(x: 0, y: y))
    textScroll.reflectScrolledClipView(clip)
  }

  func clear() {
    shownKey = nil
    textView.textStorage?.setAttributedString(NSAttributedString())
    imageView.image = nil
    quickLook?.previewItem = nil
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.labelColor.withAlphaComponent(0.05).setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
  }

  private func showClipboard(_ entry: ClipboardEntry, clipboard: ClipboardHistory) {
    var parts = ["Copied " + entry.date.formatted(.relative(presentation: .named))]
    if let source = entry.sourceAppPath {
      parts[0] += " from " + FileManager.default.displayName(atPath: source).replacing(/\.app$/, with: "")
    }
    switch entry.kind {
    case .text:
      showText(plainText(entry.text))
      parts += [characterCount(entry.text), lineCount(entry.text)]
    case .richText:
      showText(clipboard.richText(of: entry).map(readableRichText) ?? plainText(entry.text))
      parts += ["Rich text", characterCount(entry.text), lineCount(entry.text)]
    case .image:
      showImage(clipboard.imagePath(of: entry).flatMap(NSImage.init(contentsOfFile:)))
      if let width = entry.imageWidth, let height = entry.imageHeight {
        parts.append("\(width)×\(height)")
      }
    case .files where entry.filePaths.count == 1:
      showFile(URL(fileURLWithPath: entry.filePaths[0]))
      parts.append((entry.filePaths[0] as NSString).abbreviatingWithTildeInPath)
    case .files:
      showText(
        plainText(
          entry.filePaths.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(
            separator: "\n")))
      parts.append("\(entry.filePaths.count) files")
    }
    details.stringValue = parts.joined(separator: " · ")
  }

  private func showText(_ text: NSAttributedString) {
    setVisible(textScroll)
    textView.textStorage?.setAttributedString(text)
    textView.scroll(.zero)
  }

  private func showImage(_ image: NSImage?) {
    setVisible(imageView)
    imageView.image = image
  }

  private func showFile(_ url: URL) {
    let quickLook = quickLook ?? makeQuickLook()
    setVisible(quickLook)
    quickLook.previewItem = url as NSURL
  }

  private func setVisible(_ view: NSView) {
    for candidate in [textScroll, imageView, quickLook].compactMap(\.self) {
      candidate.isHidden = candidate !== view
    }
  }

  private func makeQuickLook() -> QLPreviewView {
    let view: QLPreviewView = QLPreviewView(frame: contentFrame, style: .compact)
    view.shouldCloseWithWindow = false
    addSubview(view)
    quickLook = view
    return view
  }
}

private let detailsHeight: CGFloat = 32

private func previewKey(_ preview: ResultItem.Preview) -> String {
  switch preview {
  case .clipboard(let entry): "clipboard:" + entry.id.uuidString
  case .snippet(let snippet): "snippet:" + snippet.keyword + "\u{0}" + snippet.name
  case .file(let url): "file:" + url.path
  }
}

private func plainText(_ text: String) -> NSAttributedString {
  NSAttributedString(
    string: String(text.prefix(maxPreviewLength)),
    attributes: [
      .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
      .foregroundColor: NSColor.labelColor,
    ])
}

private let maxPreviewLength = 100_000

private func characterCount(_ text: String) -> String {
  "\(text.count.formatted()) characters"
}

private func fileDetails(_ url: URL) -> String {
  var parts = [(url.path as NSString).abbreviatingWithTildeInPath]
  let values = try? url.resourceValues(forKeys: [
    .contentModificationDateKey, .fileSizeKey, .isDirectoryKey,
  ])
  if let modified = values?.contentModificationDate {
    parts.append("Modified " + modified.formatted(date: .abbreviated, time: .shortened))
  }
  if values?.isDirectory != true, let size = values?.fileSize {
    parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
  }
  return parts.joined(separator: " · ")
}

private func readableRichText(_ text: NSAttributedString) -> NSAttributedString {
  let readable = NSMutableAttributedString(
    attributedString: text.attributedSubstring(
      from: NSRange(location: 0, length: min(text.length, maxPreviewLength))))
  let range = NSRange(location: 0, length: readable.length)
  readable.removeAttribute(.backgroundColor, range: range)
  readable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
  return readable
}

private func lineCount(_ text: String) -> String {
  let lines = text.utf8.reduce(1) { $1 == 10 ? $0 + 1 : $0 }
  return lines == 1 ? "1 line" : "\(lines.formatted()) lines"
}

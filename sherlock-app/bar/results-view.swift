import AppKit
import search

final class ResultsView: NSView {
  var onClick: (Int) -> Void = { _ in }
  var onScroll: (Int) -> Void = { _ in }
  private var rows: [ResultRowView] = []
  private var scrolledRows: CGFloat = 0

  override var isFlipped: Bool { true }

  func show(_ items: ArraySlice<ResultItem>, selected: Int, icons: IconCache) {
    while rows.count < items.count {
      let row = ResultRowView()
      addSubview(row)
      rows.append(row)
    }
    for (position, row) in rows.enumerated() {
      row.isHidden = position >= items.count
      guard position < items.count else { continue }
      let item = items[items.startIndex + position]
      row.frame = NSRect(
        x: 0, y: CGFloat(position) * Layout.rowHeight, width: bounds.width,
        height: Layout.rowHeight)
      row.configure(
        item, icon: icons.image(for: item.icon),
        shortcut: position == selected ? "↩" : "⌘\(position + 1)",
        isSelected: position == selected)
    }
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    frame.contains(point) ? self : nil
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    onClick(Int(point.y / Layout.rowHeight))
  }

  override func scrollWheel(with event: NSEvent) {
    scrolledRows -= event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? Layout.rowHeight : 1)
    let rows = Int(scrolledRows)
    guard rows != 0 else { return }
    scrolledRows -= CGFloat(rows)
    onScroll(rows)
  }
}

private final class ResultRowView: NSView {
  private let iconView = NSImageView()
  private let title = makeLabel(size: 18, color: .labelColor)
  private let subtitle = makeLabel(size: 12, color: .secondaryLabelColor)
  private let shortcut = makeLabel(size: 15, color: .secondaryLabelColor)
  private var isSelected = false

  init() {
    super.init(frame: .zero)
    iconView.contentTintColor = .secondaryLabelColor
    subtitle.lineBreakMode = .byTruncatingMiddle
    shortcut.alignment = .right
    for view in [iconView, title, subtitle, shortcut] {
      addSubview(view)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  override var isFlipped: Bool { true }

  func configure(_ item: ResultItem, icon: NSImage, shortcut: String, isSelected: Bool) {
    iconView.image = icon
    iconView.imageScaling = icon.isTemplate ? .scaleNone : .scaleProportionallyUpOrDown
    title.stringValue = item.title
    subtitle.stringValue = item.subtitle
    self.shortcut.stringValue = shortcut
    if self.isSelected != isSelected {
      self.isSelected = isSelected
      needsDisplay = true
    }
  }

  override func layout() {
    super.layout()
    let width = bounds.width
    let shortcutWidth: CGFloat = 44
    let textX = 12 + Layout.iconSize + 10
    let textWidth = width - textX - shortcutWidth - 22
    iconView.frame = NSRect(
      x: 12, y: (bounds.height - Layout.iconSize) / 2, width: Layout.iconSize,
      height: Layout.iconSize)
    title.frame = NSRect(x: textX, y: 5, width: textWidth, height: 23)
    subtitle.frame = NSRect(x: textX, y: 28, width: textWidth, height: 16)
    shortcut.frame = NSRect(
      x: width - shortcutWidth - 12, y: (bounds.height - 20) / 2, width: shortcutWidth,
      height: 20)
  }

  override func draw(_ dirtyRect: NSRect) {
    guard isSelected else { return }
    NSColor.labelColor.withAlphaComponent(0.1).setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
  }
}

private func makeLabel(size: CGFloat, color: NSColor) -> NSTextField {
  let label = NSTextField(labelWithString: "")
  label.font = .systemFont(ofSize: size)
  label.textColor = color
  label.lineBreakMode = .byTruncatingTail
  label.maximumNumberOfLines = 1
  return label
}

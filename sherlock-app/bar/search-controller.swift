import AppKit
import Carbon.HIToolbox
import clipboard
import preferences
import search
import snippets

public final class SearchController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
  public var onOpenSettings: () -> Void = {}
  private let preferences: Preferences
  private let search: Search
  private let panel = SearchPanel()
  private let field = NSTextField()
  private let resultsView = ResultsView()
  private let icons = IconCache()
  private var selected = 0
  private var offset = 0
  private var top: CGFloat = 0

  public init(preferences: Preferences, clipboard: ClipboardHistory, snippets: SnippetStore) {
    self.preferences = preferences
    search = Search(clipboard: clipboard, snippets: snippets)
    super.init()
    buildViews()
    panel.delegate = self
    panel.onKeyEquivalent = { [weak self] in self?.handleKeyEquivalent($0) ?? false }
    resultsView.onClick = { [weak self] in self?.open(at: $0, reveal: false) }
    resultsView.onScroll = { [weak self] in self?.moveSelection(by: $0) }
    search.onChange = { [weak self] in self?.reload() }
    search.onIndexUpdate = { [weak self] in self?.icons.prewarm($0) }
    search.refreshIfStale()
  }

  public func toggle() {
    if panel.isVisible {
      hide()
    } else {
      show()
    }
  }

  public func show(text: String = "") {
    search.refreshIfStale()
    field.stringValue = text
    update(text)
    let mouse = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.screens[0]
    let visible = screen.visibleFrame
    top = visible.maxY - (visible.height * 0.18).rounded()
    panel.setFrame(
      NSRect(
        x: (visible.midX - Layout.width / 2).rounded(), y: top - Layout.searchHeight,
        width: Layout.width, height: Layout.searchHeight), display: false)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(field)
    field.currentEditor()?.selectedRange = NSRange(location: text.utf16.count, length: 0)
  }

  public func hide() {
    panel.orderOut(nil)
    search.stop()
  }

  public func controlTextDidChange(_ obj: Notification) {
    update(field.stringValue)
  }

  public func control(
    _ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
  ) -> Bool {
    switch selector {
    case #selector(NSResponder.moveUp(_:)): moveSelection(by: -1)
    case #selector(NSResponder.moveDown(_:)): moveSelection(by: 1)
    case #selector(NSResponder.insertNewline(_:)): open(at: selected, reveal: false)
    case #selector(NSResponder.cancelOperation(_:)): hide()
    case #selector(NSResponder.insertTab(_:)): autocomplete()
    default: return false
    }
    return true
  }

  public func windowDidResignKey(_ notification: Notification) {
    hide()
  }

  private func buildViews() {
    let background = NSVisualEffectView()
    background.material = .popover
    background.blendingMode = .behindWindow
    background.state = .active
    background.maskImage = roundedMask(radius: Layout.cornerRadius)
    panel.contentView = background

    let container = FlippedView(frame: background.bounds)
    container.autoresizingMask = [.width, .height]
    background.addSubview(container)

    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 28, weight: .light)
    field.placeholderString = "Sherlock Search"
    field.cell?.usesSingleLineMode = true
    field.cell?.isScrollable = true
    field.delegate = self
    let fieldHeight = field.intrinsicContentSize.height
    field.frame = NSRect(
      x: 18, y: ((Layout.searchHeight - fieldHeight) / 2).rounded(),
      width: Layout.width - 18 - Layout.logoSize - 26, height: fieldHeight)
    container.addSubview(field)

    let logo = NSImageView(image: NSApp.applicationIconImage)
    logo.imageScaling = .scaleProportionallyUpOrDown
    logo.frame = NSRect(
      x: Layout.width - Layout.logoSize - 14, y: (Layout.searchHeight - Layout.logoSize) / 2,
      width: Layout.logoSize, height: Layout.logoSize)
    container.addSubview(logo)

    resultsView.frame = NSRect(
      x: Layout.padding, y: Layout.searchHeight, width: Layout.width - Layout.padding * 2,
      height: 0)
    container.addSubview(resultsView)
  }

  private func update(_ text: String) {
    selected = 0
    offset = 0
    search.setKeywords(clipboard: preferences.clipboardKeyword, snippets: preferences.snippetKeyword)
    search.update(text, includeFiles: preferences.searchFiles)
    reload()
  }

  private func reload() {
    selected = min(selected, max(search.results.count - 1, 0))
    scrollToSelection()
  }

  private func moveSelection(by delta: Int) {
    guard !search.results.isEmpty else { return }
    selected = min(max(selected + delta, 0), search.results.count - 1)
    scrollToSelection()
  }

  private func scrollToSelection() {
    let results = search.results
    if selected < offset {
      offset = selected
    } else if selected >= offset + Layout.maxRows {
      offset = selected - Layout.maxRows + 1
    }
    offset = max(min(offset, results.count - Layout.maxRows), 0)
    let visible = results[offset..<min(offset + Layout.maxRows, results.count)]
    resultsView.show(visible, selected: selected - offset, icons: icons)
    resize(rows: visible.count)
  }

  private func resize(rows: Int) {
    let listHeight = CGFloat(rows) * Layout.rowHeight
    resultsView.frame.size.height = listHeight
    let height = Layout.searchHeight + (rows > 0 ? listHeight + Layout.padding : 0)
    guard panel.frame.height != height else { return }
    var frame = panel.frame
    frame.origin.y = top - height
    frame.size.height = height
    panel.setFrame(frame, display: true)
    panel.invalidateShadow()
  }

  private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
      return false
    }
    if event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter {
      open(at: selected, reveal: true)
      return true
    }
    if event.keyCode == kVK_ANSI_Comma {
      hide()
      onOpenSettings()
      return true
    }
    guard let number = event.charactersIgnoringModifiers.flatMap({ Int($0) }), number >= 1
    else { return false }
    open(at: offset + number - 1, reveal: false)
    return true
  }

  private func autocomplete() {
    guard search.results.indices.contains(selected),
      let completion = search.results[selected].autocompletion
    else { return }
    field.stringValue = completion
    field.currentEditor()?.selectedRange = NSRange(location: completion.utf16.count, length: 0)
    update(completion)
  }

  private func open(at index: Int, reveal: Bool) {
    guard search.results.indices.contains(index) else { return }
    let item = search.results[index]
    guard !item.isMessage else { return }
    if item.autocompletion != nil {
      selected = index
      autocomplete()
      return
    }
    hide()
    search.perform(item, reveal: reveal, autoPaste: preferences.autoPaste)
  }
}

private func roundedMask(radius: CGFloat) -> NSImage {
  let size = NSSize(width: radius * 2 + 1, height: radius * 2 + 1)
  let image = NSImage(size: size, flipped: false) { rect in
    NSColor.black.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    return true
  }
  image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
  image.resizingMode = .stretch
  return image
}

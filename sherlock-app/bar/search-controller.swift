import AppKit
import Carbon.HIToolbox
import clipboard
import extensions
import grok
import preferences
import search
import snippets

public final class SearchController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
  public var onOpenSettings: () -> Void = {}
  private let preferences: Preferences
  private let clipboard: ClipboardHistory
  private let search: Search
  private let panel = SearchPanel()
  private let field = NSTextField()
  private let resultsView = ResultsView()
  private let answerView = AnswerView(width: Layout.width - Layout.padding * 2)
  private let previewView = PreviewView(size: Layout.previewSize)
  private let icons = IconCache()
  private let history = QueryHistory()
  private var historyIndex: Int?
  private var selected = 0
  private var offset = 0
  private var screenFrame = NSRect.zero
  private var top: CGFloat = 0
  private var left: CGFloat?
  private var question: String?
  private var answer = ""
  private var thought = ""
  private var status: String?
  private var startsNewMessage = false
  private var answerTask: Task<Void, Never>?

  public init(
    preferences: Preferences, clipboard: ClipboardHistory, snippets: SnippetStore,
    quickLinks: QuickLinkStore, extensions: Extensions
  ) {
    self.preferences = preferences
    self.clipboard = clipboard
    search = Search(
      clipboard: clipboard, snippets: snippets, quickLinks: quickLinks, extensions: extensions,
      clipboardKeyword: preferences.clipboardKeyword, snippetKeyword: preferences.snippetKeyword)
    super.init()
    buildViews()
    panel.delegate = self
    panel.onKeyEquivalent = { [weak self] in self?.handleKeyEquivalent($0) ?? false }
    resultsView.onClick = { [weak self] row in
      guard let self else { return }
      open(at: offset + row, reveal: false)
    }
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
    let mouse = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.screens[0]
    screenFrame = screen.visibleFrame
    top = screenFrame.maxY - (screenFrame.height * 0.18).rounded()
    left = nil
    resize(width: Layout.width, listHeight: 0)
    historyIndex = nil
    field.stringValue = text
    update(text)
    left = panel.frame.minX
    panel.invalidateShadow()
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(field)
    field.currentEditor()?.selectedRange = NSRange(location: text.utf16.count, length: 0)
  }

  public func hide() {
    history.record(field.stringValue)
    closeAnswer()
    panel.orderOut(nil)
    search.stop()
    field.stringValue = ""
    selected = 0
    offset = 0
    reload()
    icons.trim()
  }

  public func controlTextDidChange(_ obj: Notification) {
    historyIndex = nil
    closeAnswer()
    update(field.stringValue)
  }

  public func control(
    _ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
  ) -> Bool {
    if question != nil {
      switch selector {
      case #selector(NSResponder.insertNewline(_:)): copyAnswer()
      case #selector(NSResponder.cancelOperation(_:)):
        closeAnswer()
        scrollToSelection()
      default: return false
      }
      return true
    }
    switch selector {
    case #selector(NSResponder.moveUp(_:)):
      if selected == 0 {
        showOlderQuery()
      } else {
        moveSelection(by: -1)
      }
    case #selector(NSResponder.moveDown(_:)): moveSelection(by: 1)
    case #selector(NSResponder.moveUpAndModifySelection(_:)) where !previewView.isHidden:
      previewView.scroll(by: -1)
    case #selector(NSResponder.moveDownAndModifySelection(_:)) where !previewView.isHidden:
      previewView.scroll(by: 1)
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
    field.autoresizingMask = [.width]
    container.addSubview(field)

    let logo = NSImageView(image: NSApp.applicationIconImage)
    logo.imageScaling = .scaleProportionallyUpOrDown
    logo.frame = NSRect(
      x: Layout.width - Layout.logoSize - 14, y: (Layout.searchHeight - Layout.logoSize) / 2,
      width: Layout.logoSize, height: Layout.logoSize)
    logo.autoresizingMask = [.minXMargin]
    container.addSubview(logo)

    resultsView.frame = NSRect(
      x: Layout.padding, y: Layout.searchHeight, width: Layout.width - Layout.padding * 2,
      height: 0)
    container.addSubview(resultsView)

    answerView.frame.origin = NSPoint(x: Layout.padding, y: Layout.searchHeight)
    answerView.isHidden = true
    container.addSubview(answerView)

    previewView.frame.origin = NSPoint(
      x: Layout.padding * 2 + Layout.previewingListWidth, y: Layout.searchHeight)
    previewView.isHidden = true
    container.addSubview(previewView)
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
    guard question == nil else { return }
    let results = search.results
    if selected < offset {
      offset = selected
    } else if selected >= offset + Layout.maxRows {
      offset = selected - Layout.maxRows + 1
    }
    offset = max(min(offset, results.count - Layout.maxRows), 0)
    let preview = results.indices.contains(selected) ? results[selected].preview : nil
    let visible = results[offset..<min(offset + Layout.maxRows, results.count)]
    resultsView.frame.size = NSSize(
      width: preview == nil ? Layout.width - Layout.padding * 2 : Layout.previewingListWidth,
      height: CGFloat(visible.count) * Layout.rowHeight)
    resultsView.show(visible, selected: selected - offset, icons: icons)
    if let preview {
      previewView.show(preview, clipboard: clipboard)
      previewView.isHidden = false
      resize(width: Layout.previewingWidth, listHeight: Layout.previewSize.height)
    } else {
      if !previewView.isHidden {
        previewView.clear()
        previewView.isHidden = true
      }
      resize(width: Layout.width, listHeight: resultsView.frame.height)
    }
  }

  private func resize(width: CGFloat = Layout.width, listHeight: CGFloat) {
    let height = Layout.searchHeight + (listHeight > 0 ? listHeight + Layout.padding : 0)
    let x = min(
      max(left ?? (screenFrame.midX - width / 2).rounded(), screenFrame.minX),
      screenFrame.maxX - width)
    let frame = NSRect(x: x, y: top - height, width: width, height: height)
    guard panel.frame != frame else { return }
    panel.setFrame(frame, display: true)
    panel.invalidateShadow()
  }

  private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
    guard question == nil, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
    else { return false }
    if event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter {
      if search.results.indices.contains(selected), search.results[selected].revealPath != nil {
        open(at: selected, reveal: true)
      }
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
    setQuery(completion)
  }

  private func showOlderQuery() {
    let index = (historyIndex ?? -1) + 1
    guard history.queries.indices.contains(index) else { return }
    historyIndex = index
    setQuery(history.queries[index])
  }

  private func setQuery(_ text: String) {
    field.stringValue = text
    field.currentEditor()?.selectedRange = NSRange(location: text.utf16.count, length: 0)
    update(text)
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
    if let question = item.question {
      ask(question)
      return
    }
    hide()
    search.perform(item, reveal: reveal, autoPaste: preferences.autoPaste)
  }

  private func ask(_ question: String) {
    closeAnswer()
    self.question = question
    resultsView.isHidden = true
    answerView.isHidden = false
    status = "Starting Grok…"
    showAnswer()
    answerTask = Task {
      do {
        try await askGrok(question) { update in
          guard !Task.isCancelled else { return }
          self.apply(update)
          self.showAnswer()
        }
        guard !Task.isCancelled else { return }
        status = nil
        showAnswer(answer.isEmpty ? "Grok didn't answer." : answer)
      } catch {
        guard !Task.isCancelled else { return }
        status = nil
        showAnswer((error as? GrokError)?.message ?? error.localizedDescription, color: .systemRed)
      }
    }
  }

  private func apply(_ update: GrokUpdate) {
    switch update {
    case .thought(let text):
      thought += text
      status = "Thinking: " + (thought.count > 500 ? "…" + thought.suffix(500) : thought)
    case .step(let title):
      thought = ""
      startsNewMessage = !answer.isEmpty
      status = title + "…"
    case .text(let text):
      if startsNewMessage {
        answer = ""
        startsNewMessage = false
      }
      thought = ""
      answer += text
      status = "Writing…"
    }
  }

  private func showAnswer(_ text: String? = nil, color: NSColor = .labelColor) {
    resize(
      listHeight: answerView.show(
        text ?? answer, color: color, status: status,
        maxHeight: CGFloat(Layout.maxRows) * Layout.rowHeight))
  }

  private func copyAnswer() {
    guard status == nil, !answer.isEmpty else { return }
    let answer = answer
    hide()
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(answer, forType: .string)
  }

  private func closeAnswer() {
    answerTask?.cancel()
    answerTask = nil
    question = nil
    answer = ""
    thought = ""
    status = nil
    startsNewMessage = false
    answerView.stopSpinner()
    answerView.isHidden = true
    resultsView.isHidden = false
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

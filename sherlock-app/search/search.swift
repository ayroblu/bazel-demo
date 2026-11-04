import AppKit
import browser
import clipboard
import conversion
import extensions
import preferences
import snippets

public final class Search {
  public var onChange: () -> Void = {}
  public var onIndexUpdate: ([String]) -> Void = { _ in }
  public private(set) var results: [ResultItem] = []
  private let clipboard: ClipboardHistory
  private let snippets: SnippetStore
  private let quickLinks: QuickLinkStore
  private let extensions: Extensions
  private let knowledge = Knowledge()
  private let fileSearch = FileSearch()
  private let exchangeRates = ExchangeRates()
  private let favicons = Favicons()
  private var candidates: [Candidate] = []
  private var history: [Candidate] = []
  private var snippetCandidates: [Candidate] = []
  private var indexedSnippetVersion = -1
  private var keywords: [KeywordMode: String] = [:]
  private var keywordItems: [Candidate] = []
  private var quickLinkItems: [Candidate] = []
  private var indexedQuickLinkVersion = -1
  private var extensionCommandItems: [Candidate] = []
  private var indexedCommands: [ExtensionCommand] = []
  private var extensionTask: Task<Void, Never>?
  private var extensionRunKey = ""
  private var extensionResultsKey = ""
  private var extensionResults: [ResultItem] = []
  private var scannedAt = Date.distantPast
  private var isScanning = false
  private var text = ""
  private var query = SearchQuery("")
  private var localResults: [ResultItem] = []
  private var fileResults: [ResultItem] = []
  private var fallbackResults: [ResultItem] = []

  public init(
    clipboard: ClipboardHistory, snippets: SnippetStore, quickLinks: QuickLinkStore,
    extensions: Extensions
  ) {
    self.clipboard = clipboard
    self.snippets = snippets
    self.quickLinks = quickLinks
    self.extensions = extensions
    favicons.onUpdate = { [weak self] in
      self?.indexedQuickLinkVersion = -1
      self?.refreshLocalResults()
      self?.onChange()
    }
    extensions.onChange = { [weak self] in
      self?.refreshLocalResults()
      self?.onChange()
    }
    setKeywords(clipboard: "clip", snippets: "snip")
    exchangeRates.onUpdate = { [weak self] in
      self?.refreshLocalResults()
      self?.onChange()
    }
  }

  public func refreshIfStale() {
    snippets.reloadIfChanged()
    quickLinks.reloadIfChanged()
    if indexedSnippetVersion != snippets.version {
      indexedSnippetVersion = snippets.version
      let snapshot = snippets.snippets
      Task { snippetCandidates = await indexSnippets(snapshot) }
    }
    guard !isScanning, Date().timeIntervalSince(scannedAt) > 30 else { return }
    isScanning = true
    Task {
      (candidates, history) = await loadCandidates()
      scannedAt = Date()
      isScanning = false
      onIndexUpdate(candidates.compactMap { filePath(of: $0.item.icon) })
      refreshLocalResults()
      onChange()
    }
  }

  public func setKeywords(clipboard: String, snippets: String) {
    let newKeywords: [KeywordMode: String] = [
      .clipboard: clipboard, .snippets: snippets, .history: "h",
    ]
    guard newKeywords != keywords else { return }
    keywords = newKeywords
    keywordItems = KeywordMode.allCases.map { keywordCandidate($0, keyword: newKeywords[$0]!) }
  }

  public func update(_ text: String, includeFiles: Bool) {
    self.text = String(text.drop { $0.isWhitespace })
    query = SearchQuery(self.text)
    let searchesFiles =
      includeFiles && keywordMode() == nil && extensionMode() == nil && query.compact.count >= 2
    fileResults =
      searchesFiles ? fileResults.filter { score(query, SearchName($0.title)) != nil } : []
    refreshLocalResults()
    guard searchesFiles else {
      fileSearch.stop()
      return
    }
    fileSearch.start(query) { [weak self] results in
      guard let self else { return }
      fileResults = results
      publish()
      onChange()
    }
  }

  public func stop() {
    fileSearch.stop()
    cancelExtensionRun()
  }

  public func perform(_ item: ResultItem, reveal: Bool, autoPaste: Bool) {
    knowledge.record(query: query.text, id: item.id)
    if reveal {
      if let path = item.revealPath {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      }
      return
    }
    switch item.action {
    case .open(let url):
      NSWorkspace.shared.open(url)
    case .copy(let string):
      copy(string)
    case .clipboard(let entry):
      clipboard.copyToPasteboard(entry)
      if autoPaste {
        pasteClipboard()
      }
    case .snippet(let snippet):
      if autoPaste {
        paste(snippets.render(snippet), restoringClipboard: true)
      } else {
        copy(snippets.render(snippet))
      }
    case .autocomplete, .none:
      break
    case .command(let command):
      command.run()
    case .extensionAction(let command, let arg):
      Task {
        if let error = await extensions.runAction(command, arg: arg) {
          showAlert("\(command.title) failed", details: error.message)
        }
      }
    }
  }

  private func refreshLocalResults() {
    fallbackResults = []
    if let (mode, argument) = keywordMode() {
      let argumentQuery = SearchQuery(argument)
      localResults =
        switch mode {
        case .clipboard: clipboardResults(argumentQuery)
        case .snippets: rank(snippetCandidates, argumentQuery, limit: nil)
        case .history: rank(history, argumentQuery, limit: argument.isEmpty ? 100 : nil)
        }
      if localResults.isEmpty {
        localResults = [emptyMessage(mode, searching: argument)]
      }
      publish()
      return
    }
    if let (command, argument) = extensionMode() {
      localResults = extensionResults(for: command)
      publish()
      runExtension(command, query: argument)
      return
    }
    cancelExtensionRun()
    guard !query.isEmpty else {
      localResults = []
      publish()
      return
    }
    if indexedQuickLinkVersion != quickLinks.version {
      indexedQuickLinkVersion = quickLinks.version
      quickLinkItems = quickLinkCandidates(quickLinks.links, favicons: favicons)
    }
    let instant = [
      quickLinkResult(text, links: quickLinks.links, favicons: favicons), calculation(text),
      conversion(text),
    ]
      .compactMap(\.self)
    if indexedCommands != extensions.commands {
      indexedCommands = extensions.commands
      extensionCommandItems = indexedCommands.map {
        extensionCommandCandidate($0, icon: extensionIcon($0))
      }
    }
    localResults =
      instant
      + rank(keywordItems + extensionCommandItems + quickLinkItems + candidates, query, limit: nil)
    fallbackResults = localResults.isEmpty ? quickLinkFallbacks(text, links: quickLinks.links, favicons: favicons) : []
    publish()
  }

  private func keywordMode() -> (KeywordMode, String)? {
    let lowercased = text.lowercased()
    for mode in KeywordMode.allCases {
      let prefix = keywords[mode]! + " "
      if lowercased.hasPrefix(prefix) {
        return (mode, String(text.dropFirst(prefix.count)))
      }
    }
    return nil
  }

  private func extensionMode() -> (ExtensionCommand, String)? {
    let lowercased = text.lowercased()
    for command in extensions.commands where lowercased.hasPrefix(command.keyword.lowercased() + " ") {
      return (command, String(text.dropFirst(command.keyword.count + 1)))
    }
    return nil
  }

  private func extensionResults(for command: ExtensionCommand) -> [ResultItem] {
    switch extensions.status(of: command) {
    case .settingUp:
      return [message("Setting up \(command.title)…", "This runs the extension's setup step")]
    case .failed(let error):
      return [message("\(command.title) isn't working", error)]
    case .ready:
      return extensionResultsKey == command.folder + command.keyword ? extensionResults : []
    }
  }

  private func runExtension(_ command: ExtensionCommand, query: String) {
    let key = command.folder + command.keyword + "\u{0}" + query
    guard key != extensionRunKey else { return }
    extensionRunKey = key
    extensionTask?.cancel()
    extensionTask = Task {
      try? await Task.sleep(for: .milliseconds(30))
      guard !Task.isCancelled else { return }
      let result = await extensions.run(command, query: query)
      guard !Task.isCancelled else { return }
      let icon = extensionIcon(command)
      switch result {
      case .success(let items):
        extensionResults = items.map {
          extensionResultItem($0, command: command, folder: extensions.buildFolder(of: command), icon: icon)
        }
        if extensionResults.isEmpty {
          extensionResults = [message("No results", "")]
        }
      case .failure(let error):
        extensionResults = [message("\(command.title) failed", error.message)]
      }
      extensionResultsKey = command.folder + command.keyword
      refreshLocalResults()
      onChange()
    }
  }

  private func cancelExtensionRun() {
    extensionTask?.cancel()
    extensionTask = nil
    extensionRunKey = ""
  }

  private func extensionIcon(_ command: ExtensionCommand) -> ResultItem.Icon {
    let icon = extensions.buildFolder(of: command).appending(path: "icon.png")
    return FileManager.default.fileExists(atPath: icon.path)
      ? .image(icon.path) : .symbol("puzzlepiece.extension")
  }

  private func conversion(_ text: String) -> ResultItem? {
    let converted =
      convertUnits(text) ?? parseCurrencyRequest(text).flatMap(exchangeRates.convert)
      ?? convertTime(text)
    return converted.map {
      ResultItem(
        id: "conversion", title: $0.result, subtitle: "\($0.detail) · ↩ copies \($0.value)",
        icon: .symbol("arrow.left.arrow.right"), action: .copy($0.value))
    }
  }

  private func clipboardResults(_ query: SearchQuery) -> [ResultItem] {
    let words = query.words.map { String(String.UnicodeScalarView($0)) }
    return clipboard.entries.filter { entry in
      let folded = fold(String(entry.text.prefix(2000)) + " " + kindLabel(entry.kind))
      return words.allSatisfy { folded.contains($0) }
    }.map { clipboardItem($0, imagePath: clipboard.imagePath(of: $0)) }
  }

  private func rank(_ candidates: [Candidate], _ query: SearchQuery, limit: Int?) -> [ResultItem] {
    guard !query.isEmpty else { return candidates.prefix(limit ?? candidates.count).map(\.item) }
    var hits: [(item: ResultItem, score: Int)] = []
    for candidate in candidates {
      guard let best = candidate.names.compactMap({ score(query, $0, fuzzy: candidate.fuzzy) }).max()
      else { continue }
      hits.append((candidate.item, best + knowledge.boost(query: query.text, id: candidate.item.id)))
    }
    hits.sort {
      if $0.score != $1.score { return $0.score > $1.score }
      if $0.item.title.count != $1.item.title.count {
        return $0.item.title.count < $1.item.title.count
      }
      return $0.item.title < $1.item.title
    }
    return hits.map(\.item)
  }

  private func publish() {
    results = localResults + fileResults + fallbackResults
  }
}

nonisolated struct Candidate: Sendable {
  let item: ResultItem
  let names: [SearchName]
  var fuzzy = true
}

private enum KeywordMode: CaseIterable {
  case clipboard
  case snippets
  case history
}

private func copy(_ string: String) {
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(string, forType: .string)
}

private func message(_ title: String, _ subtitle: String) -> ResultItem {
  ResultItem(
    id: "message", title: title, subtitle: subtitle, icon: .symbol("info.circle"), action: .none)
}

private func extensionCommandCandidate(_ command: ExtensionCommand, icon: ResultItem.Icon)
  -> Candidate
{
  let item = ResultItem(
    id: "extension:\(command.folder):\(command.keyword)", title: command.title,
    subtitle: "Type ‘\(command.keyword) ’ to search", icon: icon,
    action: .autocomplete(command.keyword + " "))
  return Candidate(item: item, names: searchNames(command.title, command.keyword), fuzzy: false)
}

private func extensionResultItem(
  _ item: ExtensionItem, command: ExtensionCommand, folder: URL, icon: ResultItem.Icon
) -> ResultItem {
  let action: Action =
    if let url = item.url.flatMap(URL.init(string:)) {
      .open(url)
    } else if let copy = item.copy {
      .copy(copy)
    } else if let arg = item.arg, command.hasAction {
      .extensionAction(command, arg)
    } else if let autocomplete = item.autocomplete {
      .autocomplete(command.keyword + " " + autocomplete)
    } else {
      .none
    }
  let itemIcon: ResultItem.Icon =
    switch item.icon {
    case .some(let name) where name.hasPrefix("sf:"): .symbol(String(name.dropFirst(3)))
    case .some(let path): .image(folder.appending(path: path).path)
    case .none: icon
    }
  return ResultItem(
    id: "extension:\(command.folder):\(item.title)", title: item.title,
    subtitle: item.subtitle ?? "", icon: itemIcon, action: action)
}

private func emptyMessage(_ mode: KeywordMode, searching argument: String) -> ResultItem {
  let (title, subtitle) =
    switch (mode, argument.isEmpty) {
    case (.clipboard, true):
      ("No clipboard history yet", "Text you copy from now on appears here")
    case (.snippets, true):
      ("No snippets yet", "Import Alfred snippets or add your own in Settings (⌘,)")
    case (.history, true):
      ("No browser history", "Safari history needs Full Disk Access (Settings, ⌘,)")
    case (.clipboard, false): ("No clipboard items match ‘\(argument)’", "")
    case (.snippets, false): ("No snippets match ‘\(argument)’", "")
    case (.history, false): ("No pages match ‘\(argument)’", "")
    }
  return message(title, subtitle)
}

@concurrent private func loadCandidates() async -> ([Candidate], [Candidate]) {
  let local =
    scanApplications() + scanSettingsPanes() + commandCandidates()
    + loadBookmarks().map { webPageCandidate($0, subtitle: "Bookmark · ") }
  return (local, loadHistory().map { webPageCandidate($0, subtitle: "") })
}

@concurrent private func indexSnippets(_ snippets: [Snippet]) async -> [Candidate] {
  snippets.map(snippetCandidate)
}

private func keywordCandidate(_ mode: KeywordMode, keyword: String) -> Candidate {
  let (title, symbol, name) =
    switch mode {
    case .clipboard: ("Clipboard History", "doc.on.clipboard", "clipboard")
    case .snippets: ("Snippets", "text.quote", "snippets")
    case .history: ("Browser History", "clock.arrow.circlepath", "history")
    }
  let item = ResultItem(
    id: "keyword:\(mode)", title: title, subtitle: "Type ‘\(keyword) ’ to search",
    icon: .symbol(symbol), action: .autocomplete(keyword + " "))
  return Candidate(item: item, names: searchNames(title, name, keyword))
}

private nonisolated func webPageCandidate(_ page: WebPage, subtitle: String) -> Candidate {
  let address = page.url.absoluteString.replacing(/^https?:\/\/(www\.)?/, with: "")
  let item = ResultItem(
    id: page.url.absoluteString, title: page.title.isEmpty ? address : page.title,
    subtitle: subtitle + address, icon: .file(page.browserPath), action: .open(page.url))
  return Candidate(
    item: item, names: searchNames(page.title, page.url.host() ?? ""), fuzzy: false)
}

private nonisolated func snippetCandidate(_ snippet: Snippet) -> Candidate {
  let preview = snippet.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
  let item = ResultItem(
    id: "snippet:" + snippet.keyword + snippet.name, title: snippet.name,
    subtitle: [snippet.keyword, String(preview.prefix(120))].filter { !$0.isEmpty }.joined(
      separator: " · "),
    icon: .symbol("text.quote"), action: .snippet(snippet))
  return Candidate(
    item: item, names: searchNames(snippet.name, snippet.keyword), fuzzy: false)
}

private func clipboardItem(_ entry: ClipboardEntry, imagePath: String?) -> ResultItem {
  let lines = entry.text.split(whereSeparator: \.isNewline)
  let firstLine = lines.first { !$0.allSatisfy(\.isWhitespace) } ?? ""
  let age = entry.date.formatted(.relative(presentation: .named))
  let source = entry.sourceAppPath.map {
    FileManager.default.displayName(atPath: $0).replacing(/\.app$/, with: "")
  }
  let title: String
  let detail: String?
  let icon: ResultItem.Icon
  switch entry.kind {
  case .image:
    title = "Image"
    detail = entry.imageWidth.map { "\($0)×\(entry.imageHeight ?? 0)" }
    icon = imagePath.map { .image($0) } ?? .symbol("photo")
  case .files:
    let names = entry.filePaths.map { ($0 as NSString).lastPathComponent }
    title = names.joined(separator: ", ")
    detail = names.count > 1 ? "\(names.count) files" : (entry.filePaths.first as NSString?)?.abbreviatingWithTildeInPath
    icon = .file(entry.filePaths[0])
  case .text, .richText:
    title = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    let notes = [entry.kind == .richText ? "Rich text" : nil, lines.count > 1 ? "\(lines.count) lines" : nil]
      .compactMap(\.self)
    detail = notes.isEmpty ? nil : notes.joined(separator: ", ")
    icon = entry.sourceAppPath.map { .file($0) } ?? .symbol("doc.on.clipboard")
  }
  return ResultItem(
    id: "clipboard", title: String(title.prefix(200)),
    subtitle: [age, source, detail].compactMap(\.self).joined(separator: " · "), icon: icon,
    action: .clipboard(entry))
}

private func kindLabel(_ kind: ClipboardEntry.Kind) -> String {
  switch kind {
  case .text: ""
  case .richText: "rich text"
  case .image: "image"
  case .files: "file files"
  }
}

private func filePath(of icon: ResultItem.Icon) -> String? {
  guard case .file(let path) = icon else { return nil }
  return path
}

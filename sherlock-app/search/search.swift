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
  private var clipboardSummaries: [UUID: ClipboardSummary] = [:]
  private var sourceNames: [String: String] = [:]
  private var scannedAt = Date.distantPast
  private var isScanning = false
  private var text = ""
  private var query = SearchQuery("")
  private var rankedQuery = ""
  private var localResults: [ResultItem] = []
  private var fileResults: [ResultItem] = []
  private var fallbackResults: [ResultItem] = []

  public init(
    clipboard: ClipboardHistory, snippets: SnippetStore, quickLinks: QuickLinkStore,
    extensions: Extensions, clipboardKeyword: String, snippetKeyword: String
  ) {
    self.clipboard = clipboard
    self.snippets = snippets
    self.quickLinks = quickLinks
    self.extensions = extensions
    setKeywords(clipboard: clipboardKeyword, snippets: snippetKeyword)
    favicons.onUpdate = { [weak self] in
      self?.indexedQuickLinkVersion = -1
      self?.refresh()
    }
    extensions.onChange = { [weak self] in self?.refresh() }
    exchangeRates.onUpdate = { [weak self] in self?.refresh() }
  }

  public func refreshIfStale() {
    if indexedSnippetVersion != snippets.version {
      let version = snippets.version
      indexedSnippetVersion = version
      let snapshot = snippets.items
      Task {
        let indexed = await indexSnippets(snapshot)
        guard version == snippets.version else { return }
        snippetCandidates = indexed
        refresh()
      }
    }
    guard !isScanning, Date().timeIntervalSince(scannedAt) > 30 else { return }
    isScanning = true
    Task {
      (candidates, history) = await loadCandidates()
      scannedAt = Date()
      isScanning = false
      onIndexUpdate(candidates.compactMap { filePath(of: $0.item.icon) })
      refresh()
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
    let query = rankedQuery
    update("", includeFiles: false)
    rankedQuery = query
  }

  public func perform(_ item: ResultItem, reveal: Bool, autoPaste: Bool) {
    knowledge.record(query: rankedQuery, id: item.id)
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
        paste(snippets.render(snippet))
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

  private func refresh() {
    refreshLocalResults()
    onChange()
  }

  private func refreshLocalResults() {
    fallbackResults = []
    rankedQuery = query.text
    if let (mode, argument) = keywordMode() {
      let argumentQuery = SearchQuery(argument)
      rankedQuery = argumentQuery.text
      localResults =
        switch mode {
        case .clipboard: clipboardResults(argumentQuery)
        case .snippets: rank(snippetCandidates, argumentQuery)
        case .history: rank(argument.isEmpty ? Array(history.prefix(100)) : history, argumentQuery)
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
      quickLinkItems = quickLinkCandidates(quickLinks.items, favicons: favicons)
    }
    if indexedCommands != extensions.commands {
      indexedCommands = extensions.commands
      extensionCommandItems = indexedCommands.map {
        extensionCommandCandidate($0, icon: extensionIcon($0))
      }
    }
    let instant = [
      quickLinkResult(text, links: quickLinks.items, favicons: favicons), calculation(text),
      conversion(text),
    ].compactMap(\.self)
    localResults =
      instant + rank(keywordItems + extensionCommandItems + quickLinkItems + candidates, query)
    if localResults.isEmpty {
      fallbackResults = quickLinkFallbacks(text, links: quickLinks.items, favicons: favicons)
    }
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
    for command in extensions.commands
    where lowercased.hasPrefix(command.keyword.lowercased() + " ") {
      return (command, String(text.dropFirst(command.keyword.count + 1)))
    }
    return nil
  }

  private func clipboardResults(_ query: SearchQuery) -> [ResultItem] {
    let words = query.words.map { String(String.UnicodeScalarView($0)) }
    let entries = clipboard.entries
    if clipboardSummaries.count > entries.count * 2 {
      clipboardSummaries = [:]
    }
    return entries.compactMap { entry in
      let summary = clipboardSummary(entry)
      guard words.allSatisfy({ summary.folded.contains($0) }) else { return nil }
      return clipboardItem(
        entry, summary: summary, source: sourceName(entry.sourceAppPath),
        imagePath: clipboard.imagePath(of: entry))
    }
  }

  private func clipboardSummary(_ entry: ClipboardEntry) -> ClipboardSummary {
    if let summary = clipboardSummaries[entry.id] { return summary }
    let summary = summarize(entry)
    clipboardSummaries[entry.id] = summary
    return summary
  }

  private func sourceName(_ path: String?) -> String? {
    guard let path else { return nil }
    if let name = sourceNames[path] { return name }
    let name = FileManager.default.displayName(atPath: path).replacing(/\.app$/, with: "")
    sourceNames[path] = name
    return name
  }

  private func rank(_ items: [Candidate], _ query: SearchQuery) -> [ResultItem] {
    guard !query.isEmpty else { return items.map(\.item) }
    var hits: [(item: ResultItem, score: Int, titleLength: Int)] = []
    for candidate in items {
      guard let best = candidate.names.compactMap({ score(query, $0, fuzzy: candidate.fuzzy) }).max()
      else { continue }
      hits.append(
        (
          candidate.item, best + knowledge.boost(query: query.text, id: candidate.item.id),
          candidate.item.title.count
        ))
    }
    hits.sort {
      if $0.score != $1.score { return $0.score > $1.score }
      if $0.titleLength != $1.titleLength { return $0.titleLength < $1.titleLength }
      return $0.item.title < $1.item.title
    }
    return hits.map(\.item)
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
          extensionResultItem(
            $0, command: command, folder: extensions.buildFolder(of: command), icon: icon)
        }
        if extensionResults.isEmpty {
          extensionResults = [message("No results", "")]
        }
      case .failure(let error):
        extensionResults = [message("\(command.title) failed", error.message)]
      }
      extensionResultsKey = command.folder + command.keyword
      refresh()
    }
  }

  private func cancelExtensionRun() {
    extensionTask?.cancel()
    extensionTask = nil
    extensionRunKey = ""
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

private struct ClipboardSummary {
  let folded: String
  let title: String
  let lineCount: Int
}

private func copy(_ string: String) {
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(string, forType: .string)
}

@concurrent private func indexSnippets(_ snippets: [Snippet]) async -> [Candidate] {
  snippets.map(snippetCandidate)
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

@concurrent private func loadCandidates() async -> ([Candidate], [Candidate]) {
  let local =
    scanApplications() + scanSettingsPanes() + commandCandidates()
    + loadBookmarks().map { webPageCandidate($0, subtitle: "Bookmark · ") }
  return (local, loadHistory().map { webPageCandidate($0, subtitle: "") })
}

private nonisolated func webPageCandidate(_ page: WebPage, subtitle: String) -> Candidate {
  let address = page.url.absoluteString.replacing(/^https?:\/\/(www\.)?/, with: "")
  let item = ResultItem(
    id: page.url.absoluteString, title: page.title.isEmpty ? address : page.title,
    subtitle: subtitle + address, icon: .file(page.browserPath), action: .open(page.url))
  return Candidate(
    item: item, names: searchNames(page.title, page.url.host() ?? ""), fuzzy: false)
}

private func filePath(of icon: ResultItem.Icon) -> String? {
  guard case .file(let path) = icon else { return nil }
  return path
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

private func emptyMessage(_ mode: KeywordMode, searching argument: String) -> ResultItem {
  let (title, subtitle) =
    switch (mode, argument.isEmpty) {
    case (.clipboard, true):
      ("No clipboard history yet", "What you copy from now on appears here")
    case (.snippets, true):
      ("No snippets yet", "Add them to snippets.yaml from Settings (⌘,)")
    case (.history, true):
      ("No browser history", "Safari history needs Full Disk Access (Settings, ⌘,)")
    case (.clipboard, false): ("No clipboard items match ‘\(argument)’", "")
    case (.snippets, false): ("No snippets match ‘\(argument)’", "")
    case (.history, false): ("No pages match ‘\(argument)’", "")
    }
  return message(title, subtitle)
}

private func message(_ title: String, _ subtitle: String) -> ResultItem {
  ResultItem(
    id: "message", title: title, subtitle: subtitle, icon: .symbol("info.circle"), action: .none)
}

private func summarize(_ entry: ClipboardEntry) -> ClipboardSummary {
  let folded = fold(String(entry.text.prefix(2000)) + " " + kindLabel(entry.kind))
  switch entry.kind {
  case .image:
    return ClipboardSummary(folded: folded, title: "Image", lineCount: 1)
  case .files:
    let names = entry.filePaths.map { ($0 as NSString).lastPathComponent }
    return ClipboardSummary(
      folded: folded, title: names.joined(separator: ", "), lineCount: names.count)
  case .text, .richText:
    let firstLine =
      entry.text.prefix(10_000).split(whereSeparator: \.isNewline)
      .first { !$0.allSatisfy(\.isWhitespace) } ?? ""
    return ClipboardSummary(
      folded: folded,
      title: String(firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(200)),
      lineCount: entry.text.utf8.reduce(1) { $1 == 10 ? $0 + 1 : $0 })
  }
}

private func kindLabel(_ kind: ClipboardEntry.Kind) -> String {
  switch kind {
  case .text: ""
  case .richText: "rich text"
  case .image: "image"
  case .files: "files"
  }
}

private func clipboardItem(
  _ entry: ClipboardEntry, summary: ClipboardSummary, source: String?, imagePath: String?
) -> ResultItem {
  let detail: String?
  let icon: ResultItem.Icon
  switch entry.kind {
  case .image:
    detail = entry.imageWidth.map { "\($0)×\(entry.imageHeight ?? 0)" }
    icon = imagePath.map { .image($0) } ?? .symbol("photo")
  case .files:
    detail =
      summary.lineCount > 1
      ? "\(summary.lineCount) files"
      : (entry.filePaths[0] as NSString).abbreviatingWithTildeInPath
    icon = .file(entry.filePaths[0])
  case .text, .richText:
    let notes = [
      entry.kind == .richText ? "Rich text" : nil,
      summary.lineCount > 1 ? "\(summary.lineCount) lines" : nil,
    ].compactMap(\.self)
    detail = notes.isEmpty ? nil : notes.joined(separator: ", ")
    icon = entry.sourceAppPath.map { .file($0) } ?? .symbol("doc.on.clipboard")
  }
  let age = entry.date.formatted(.relative(presentation: .named))
  return ResultItem(
    id: "clipboard", title: summary.title,
    subtitle: [age, source, detail].compactMap(\.self).joined(separator: " · "), icon: icon,
    action: .clipboard(entry))
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

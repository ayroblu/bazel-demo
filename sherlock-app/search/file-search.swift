import CoreServices
import Foundation

public func hasFullDiskAccess() -> Bool {
  let descriptor = open(home + "/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
  guard descriptor >= 0 else { return false }
  close(descriptor)
  return true
}

final class FileSearch {
  private var query: MDQuery?
  private var searchQuery = SearchQuery("")
  private var observers: [NSObjectProtocol] = []
  private var onResults: ([ResultItem]) -> Void = { _ in }

  func start(_ searchQuery: SearchQuery, onResults: @escaping ([ResultItem]) -> Void) {
    stop()
    guard
      let query = MDQueryCreate(
        kCFAllocatorDefault, spotlightQuery(searchQuery) as CFString, fetchedAttributes as CFArray,
        nil)
    else { return }
    MDQuerySetMaxCount(query, 200)
    MDQuerySetSearchScope(query, [kMDQueryScopeHome] as [CFString] as CFArray, 0)
    MDQuerySetBatchingParameters(
      query,
      MDQueryBatchingParams(
        first_max_num: 50, first_max_ms: 15, progress_max_num: 200, progress_max_ms: 50,
        update_max_num: 0, update_max_ms: 0))
    for name in [kMDQueryProgressNotification, kMDQueryDidFinishNotification].compactMap(\.self) {
      observers.append(
        NotificationCenter.default.addObserver(
          forName: Notification.Name(name as String), object: query, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.publish() }
        })
    }
    self.query = query
    self.searchQuery = searchQuery
    self.onResults = onResults
    MDQueryExecute(query, 0)
  }

  func stop() {
    guard let query else { return }
    MDQueryStop(query)
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    self.query = nil
  }

  private func publish() {
    guard let query else { return }
    var hits: [(item: ResultItem, score: Int, date: Date)] = []
    for index in 0..<MDQueryGetResultCount(query) {
      let item = unsafeBitCast(MDQueryGetResultAtIndex(query, index), to: MDItem.self)
      guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String, isUseful(path) else {
        continue
      }
      let name: String =
        attribute(query, kMDItemDisplayName, index) ?? (path as NSString).lastPathComponent
      let lastUsed: Date? = attribute(query, kMDItemLastUsedDate, index)
      let changed: Date? = attribute(query, kMDItemFSContentChangeDate, index)
      let matchScore = score(searchQuery, SearchName(name)) ?? 0
      hits.append(
        (
          fileItem(path: path, title: name), matchScore + (lastUsed == nil ? 0 : 150),
          lastUsed ?? changed ?? .distantPast
        ))
    }
    hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.date > $1.date }
    onResults(hits.prefix(maxResults).map(\.item))
  }
}

private nonisolated func spotlightQuery(_ query: SearchQuery) -> String {
  let terms = query.words.map { word in
    var escaped = ""
    for scalar in word {
      if "\"\\*?".unicodeScalars.contains(scalar) { escaped += "\\" }
      escaped.unicodeScalars.append(scalar)
    }
    return "kMDItemDisplayName == \"\(escaped)*\"cdw"
  }
  let exclusions = [
    "kMDItemContentType != \"com.apple.application-bundle\"", "kMDItemContentType != \"dyn*\"",
  ]
  return (terms + exclusions).joined(separator: " && ")
}

private let fetchedAttributes: [CFString] = [
  kMDItemDisplayName, kMDItemLastUsedDate, kMDItemFSContentChangeDate,
]

private func isUseful(_ path: String) -> Bool {
  if path.hasPrefix(home + "/Library/") {
    return path.hasPrefix(home + "/Library/Mobile Documents/")
  }
  return !path.contains("/.") && !path.contains("/node_modules/")
}

private let home = NSHomeDirectory()

private func attribute<T>(_ query: MDQuery, _ name: CFString, _ index: Int) -> T? {
  guard let value = MDQueryGetAttributeValueOfResultAtIndex(query, name, index) else {
    return nil
  }
  return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue() as? T
}

private let maxResults = 30

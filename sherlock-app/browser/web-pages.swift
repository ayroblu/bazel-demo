import Foundation
import SQLite3

public struct WebPage: Sendable {
  public let title: String
  public let url: URL
  public let browserPath: String
  public let lastVisit: Date?
}

public func loadBookmarks() -> [WebPage] {
  uniqueWebPages(safariBookmarks() + chromeProfiles().flatMap(chromeBookmarks))
}

public func loadHistory() -> [WebPage] {
  uniqueWebPages(
    (safariHistory() + chromeProfiles().flatMap(chromeHistory))
      .sorted { ($0.lastVisit ?? .distantPast) > ($1.lastVisit ?? .distantPast) })
}

public func loadFavicons() -> [String: Data] {
  chromeProfiles().reduce(into: [:]) { icons, profile in
    icons.merge(chromeFavicons(profile)) { current, _ in current }
  }
}

private func uniqueWebPages(_ pages: [WebPage]) -> [WebPage] {
  var seen = Set<URL>()
  return pages.filter {
    ($0.url.scheme == "https" || $0.url.scheme == "http") && seen.insert($0.url).inserted
  }
}

private let home = URL(fileURLWithPath: NSHomeDirectory())
private let safariPath = "/Applications/Safari.app"
private let chromePath = "/Applications/Google Chrome.app"
private let historyLimit = 3000

private func safariBookmarks() -> [WebPage] {
  guard
    let root = NSDictionary(contentsOf: home.appending(path: "Library/Safari/Bookmarks.plist"))
      as? [String: Any]
  else { return [] }
  var pages: [WebPage] = []
  collectSafariBookmarks(root, into: &pages)
  return pages
}

private func collectSafariBookmarks(_ node: [String: Any], into pages: inout [WebPage]) {
  if node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf",
    let urlString = node["URLString"] as? String, let url = URL(string: urlString)
  {
    let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String
    pages.append(
      WebPage(title: title ?? urlString, url: url, browserPath: safariPath, lastVisit: nil))
  }
  for child in node["Children"] as? [[String: Any]] ?? [] {
    collectSafariBookmarks(child, into: &pages)
  }
}

private func chromeProfiles() -> [URL] {
  let root = home.appending(path: "Library/Application Support/Google/Chrome")
  let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
  return names.filter { $0 == "Default" || $0.hasPrefix("Profile ") }.map {
    root.appending(path: $0)
  }
}

private func chromeBookmarks(_ profile: URL) -> [WebPage] {
  chromeBookmarkFiles.flatMap { readChromeBookmarks(profile.appending(path: $0)) }
}

private let chromeBookmarkFiles = ["Bookmarks", "AccountBookmarks"]

private func readChromeBookmarks(_ file: URL) -> [WebPage] {
  guard let data = try? Data(contentsOf: file),
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let roots = json["roots"] as? [String: Any]
  else { return [] }
  var pages: [WebPage] = []
  for case let root as [String: Any] in roots.values {
    collectChromeBookmarks(root, into: &pages)
  }
  return pages
}

private func collectChromeBookmarks(_ node: [String: Any], into pages: inout [WebPage]) {
  if node["type"] as? String == "url", let urlString = node["url"] as? String,
    let url = URL(string: urlString)
  {
    pages.append(
      WebPage(
        title: node["name"] as? String ?? urlString, url: url, browserPath: chromePath,
        lastVisit: nil))
  }
  for child in node["children"] as? [[String: Any]] ?? [] {
    collectChromeBookmarks(child, into: &pages)
  }
}

private func safariHistory() -> [WebPage] {
  let query = """
    SELECT i.url, v.title, MAX(v.visit_time) FROM history_items i
    JOIN history_visits v ON v.history_item = i.id
    GROUP BY i.id ORDER BY MAX(v.visit_time) DESC LIMIT \(historyLimit)
    """
  return queryDatabase(home.appending(path: "Library/Safari/History.db"), query) { row in
    row.url(0).map {
      WebPage(
        title: row.text(1) ?? "", url: $0, browserPath: safariPath,
        lastVisit: Date(timeIntervalSinceReferenceDate: row.double(2)))
    }
  }
}

private func chromeHistory(_ profile: URL) -> [WebPage] {
  let query = """
    SELECT url, title, last_visit_time FROM urls WHERE hidden = 0
    ORDER BY last_visit_time DESC LIMIT \(historyLimit)
    """
  return queryDatabase(profile.appending(path: "History"), query) { row in
    row.url(0).map {
      WebPage(
        title: row.text(1) ?? "", url: $0, browserPath: chromePath,
        lastVisit: Date(timeIntervalSince1970: row.double(2) / 1_000_000 - chromeEpochOffset))
    }
  }
}

private let chromeEpochOffset: Double = 11_644_473_600

private func chromeFavicons(_ profile: URL) -> [String: Data] {
  let query = """
    SELECT m.page_url, b.id, b.image_data FROM icon_mapping m
    JOIN favicon_bitmaps b ON b.icon_id = m.icon_id ORDER BY b.width
    """
  var images: [Int64: Data] = [:]
  let pages = queryDatabase(profile.appending(path: "Favicons"), query) { row in
    let bitmap = row.int(1)
    if images[bitmap] == nil {
      images[bitmap] = row.data(2)
    }
    return row.text(0).map { ($0, bitmap) }
  }
  return Dictionary(pages) { _, larger in larger }.compactMapValues { images[$0] }
}

private func queryDatabase<T>(_ database: URL, _ query: String, _ makeRow: (Row) -> T?) -> [T] {
  let copy = FileManager.default.temporaryDirectory.appending(path: "sherlock-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: copy) }
  do {
    try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
    for suffix in ["", "-wal"] {
      let source = URL(fileURLWithPath: database.path + suffix)
      if FileManager.default.fileExists(atPath: source.path) {
        try FileManager.default.copyItem(
          at: source, to: copy.appending(path: database.lastPathComponent + suffix))
      }
    }
  } catch {
    return []
  }
  var handle: OpaquePointer?
  guard
    sqlite3_open(copy.appending(path: database.lastPathComponent).path, &handle) == SQLITE_OK
  else { return [] }
  defer { sqlite3_close(handle) }
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK else { return [] }
  defer { sqlite3_finalize(statement) }
  var rows: [T] = []
  while sqlite3_step(statement) == SQLITE_ROW {
    if let row = makeRow(Row(statement: statement)) {
      rows.append(row)
    }
  }
  return rows
}

private struct Row {
  let statement: OpaquePointer?

  func text(_ column: Int32) -> String? {
    sqlite3_column_text(statement, column).map { String(cString: $0) }
  }

  func url(_ column: Int32) -> URL? {
    text(column).flatMap(URL.init(string:))
  }

  func double(_ column: Int32) -> Double {
    sqlite3_column_double(statement, column)
  }

  func int(_ column: Int32) -> Int64 {
    sqlite3_column_int64(statement, column)
  }

  func data(_ column: Int32) -> Data? {
    sqlite3_column_blob(statement, column).map {
      Data(bytes: $0, count: Int(sqlite3_column_bytes(statement, column)))
    }
  }
}

import AppKit

func keywordSearch(_ text: String) -> ResultItem? {
  let parts = text.split(separator: " ", maxSplits: 1)
  guard parts.count == 2,
    let engine = engines.first(where: { $0.keywords.contains(parts[0].lowercased()) })
  else { return nil }
  let terms = parts[1].trimmingCharacters(in: .whitespaces)
  return terms.isEmpty ? nil : engine.item(searching: terms)
}

func webFallback(_ text: String) -> ResultItem {
  engines[0].item(searching: text)
}

private struct WebSearchEngine {
  let id: String
  let name: String
  let keywords: [String]
  let template: String
  let appPath: String?

  func item(searching terms: String) -> ResultItem {
    let encoded = terms.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? terms
    let url = URL(string: template.replacingOccurrences(of: "{query}", with: encoded))!
    return ResultItem(
      id: "web:" + id, title: "Search \(name) for ‘\(terms)’",
      subtitle: [url.host(), "keyword: \(keywords[0])"].compactMap(\.self).joined(separator: " · "),
      icon: .file(appPath ?? defaultBrowserPath()), action: .open(url))
  }
}

private let engines = [
  WebSearchEngine(
    id: "google", name: "Google", keywords: ["g", "google"],
    template: "https://www.google.com/search?q={query}", appPath: nil),
  WebSearchEngine(
    id: "youtube", name: "YouTube", keywords: ["yt", "youtube"],
    template: "https://www.youtube.com/results?search_query={query}", appPath: nil),
  WebSearchEngine(
    id: "wikipedia", name: "Wikipedia", keywords: ["wiki"],
    template: "https://en.wikipedia.org/wiki/Special:Search?search={query}", appPath: nil),
  WebSearchEngine(
    id: "github", name: "GitHub", keywords: ["gh", "github"],
    template: "https://github.com/search?q={query}", appPath: nil),
  WebSearchEngine(
    id: "maps", name: "Maps", keywords: ["maps"], template: "maps://?q={query}",
    appPath: "/System/Applications/Maps.app"),
]

private let queryAllowed = CharacterSet.urlQueryAllowed.subtracting(
  CharacterSet(charactersIn: "&+=#?/"))

private func defaultBrowserPath() -> String {
  NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)?.path
    ?? "/Applications/Safari.app"
}

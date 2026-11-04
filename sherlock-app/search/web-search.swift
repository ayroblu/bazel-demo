import AppKit
import preferences

func quickLinkResult(_ text: String, links: [QuickLink]) -> ResultItem? {
  let parts = text.split(separator: " ", maxSplits: 1)
  guard parts.count == 2,
    let link = links.first(where: { $0.keyword.lowercased() == parts[0].lowercased() }),
    link.url.contains(queryPlaceholder)
  else { return nil }
  let terms = parts[1].trimmingCharacters(in: .whitespaces)
  return terms.isEmpty ? nil : item(for: link, searching: terms)
}

func quickLinkFallbacks(_ text: String, links: [QuickLink]) -> [ResultItem] {
  links.filter { $0.fallback == true && $0.url.contains(queryPlaceholder) }.compactMap {
    item(for: $0, searching: text)
  }
}

func quickLinkCandidates(_ links: [QuickLink]) -> [Candidate] {
  links.compactMap { link in
    let takesQuery = link.url.contains(queryPlaceholder)
    guard let url = URL(string: link.url.replacing(queryPlaceholder, with: "")) else { return nil }
    let title = link.title.replacing(queryPlaceholder, with: "…")
    let item = ResultItem(
      id: "quicklink:" + link.keyword, title: title,
      subtitle: takesQuery ? "Type ‘\(link.keyword) ’ and your search" : link.url,
      icon: .file(appPath(opening: url)),
      action: takesQuery ? .autocomplete(link.keyword + " ") : .open(url))
    let words = link.title.replacing(queryPlaceholder, with: "")
    return Candidate(item: item, names: searchNames(link.keyword, words), fuzzy: false)
  }
}

func appPath(opening url: URL) -> String {
  NSWorkspace.shared.urlForApplication(toOpen: url)?.path ?? "/Applications/Safari.app"
}

private let queryPlaceholder = "{query}"

private func item(for link: QuickLink, searching terms: String) -> ResultItem? {
  let encoded = terms.split(separator: " ").map {
    $0.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? String($0)
  }.joined(separator: link.spaces ?? "%20")
  guard let url = URL(string: link.url.replacing(queryPlaceholder, with: encoded)) else {
    return nil
  }
  return ResultItem(
    id: "quicklink:" + link.keyword, title: link.title.replacing(queryPlaceholder, with: terms),
    subtitle: [url.host(), "keyword: \(link.keyword)"].compactMap(\.self).joined(separator: " · "),
    icon: .file(appPath(opening: url)), action: .open(url))
}

private let queryAllowed = CharacterSet.urlQueryAllowed.subtracting(
  CharacterSet(charactersIn: "&+=#?/"))

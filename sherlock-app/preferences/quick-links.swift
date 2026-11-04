import Foundation

public nonisolated struct QuickLink: Codable, Sendable, Equatable {
  public var keyword: String
  public var title: String
  public var url: String
  public var spaces: String?
  public var fallback: Bool?
}

public typealias QuickLinkStore = ConfigList<QuickLink>

extension ConfigList where Item == QuickLink {
  public convenience init(quickLinksIn folder: URL) {
    self.init(folder: folder, name: "quicklinks.yaml", defaults: standardQuickLinks)
  }
}

private let standardQuickLinks = [
  QuickLink(
    keyword: "g", title: "Search Google for ‘{query}’",
    url: "https://www.google.com/search?q={query}", fallback: true),
  QuickLink(
    keyword: "yt", title: "Search YouTube for ‘{query}’",
    url: "https://www.youtube.com/results?search_query={query}"),
  QuickLink(
    keyword: "wiki", title: "Search Wikipedia for ‘{query}’",
    url: "https://en.wikipedia.org/wiki/Special:Search?search={query}"),
  QuickLink(
    keyword: "gh", title: "Search GitHub for ‘{query}’", url: "https://github.com/search?q={query}",
    spaces: "+"),
  QuickLink(keyword: "maps", title: "Search Maps for ‘{query}’", url: "maps://?q={query}"),
]

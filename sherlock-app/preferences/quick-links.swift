import Foundation

public nonisolated struct QuickLink: Codable, Sendable, Equatable {
  public var keyword: String
  public var title: String
  public var url: String
  public var spaces: String?
  public var fallback: Bool?

  public init(
    keyword: String, title: String, url: String, spaces: String? = nil, fallback: Bool? = nil
  ) {
    self.keyword = keyword
    self.title = title
    self.url = url
    self.spaces = spaces
    self.fallback = fallback
  }
}

public final class QuickLinkStore {
  public private(set) var links: [QuickLink] = []
  public private(set) var version = 0
  private let file: ConfigFile<[QuickLink]>

  public init(folder: URL) {
    file = ConfigFile(folder: folder, name: "quicklinks.yaml")
    if !file.exists {
      try? file.save(standardQuickLinks)
    }
    load()
  }

  public var fileURL: URL { file.url }

  public func reloadIfChanged() {
    guard file.hasChanged else { return }
    load()
  }

  public func moveFolder(to folder: URL) throws {
    try file.move(to: folder)
    load()
  }

  private func load() {
    guard let loaded = file.load() ?? (file.exists ? nil : []) else { return }
    links = loaded
    version += 1
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

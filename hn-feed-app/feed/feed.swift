import FileUtils
import Foundation

public enum FeedSource: String, Sendable {
  case newsyc200
  case newsyc250
  case frontPage
  case rising
}

public struct Feed: Sendable {
  public let items: [FeedItem]
  public let fetchedAt: Date
}

public struct FeedItem: Codable, Identifiable, Hashable, Sendable {
  public let id: Int
  public let title: String
  public let link: URL
  public let hnlink: URL
  public let author: String?
  public let ts: Date
}

@concurrent
public func loadCachedFeed(_ source: FeedSource) async -> Feed? {
  let url = cacheURL(source)
  guard let data = try? Data(contentsOf: url),
    let items = try? parseFeed(data),
    let fetchedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey])
      .contentModificationDate
  else { return nil }
  return Feed(items: items, fetchedAt: fetchedAt)
}

@concurrent
public func downloadFeed(_ source: FeedSource) async throws -> Feed {
  let items =
    switch source {
    case .newsyc200: try await downloadBlueskyFeed(actor: "newsyc200.bsky.social")
    case .newsyc250: try await downloadBlueskyFeed(actor: "newsyc250.bsky.social")
    case .frontPage: try await downloadFrontPage()
    case .rising: try parseFeed(try await getData(risingFeedURL))
    }
  try encodeFeed(items).write(to: cacheURL(source), options: .atomic)
  return Feed(items: items, fetchedAt: Date())
}

private func cacheURL(_ source: FeedSource) -> URL {
  FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    / "hn-feed-\(source.rawValue).jsonl"
}

private func parseFeed(_ data: Data) throws -> [FeedItem] {
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .secondsSince1970
  return try data.split(separator: UInt8(ascii: "\n")).map {
    try decoder.decode(FeedItem.self, from: Data($0))
  }
}

private func downloadBlueskyFeed(actor: String) async throws -> [FeedItem] {
  var components = URLComponents(
    string: "https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed")!
  components.queryItems = [
    URLQueryItem(name: "actor", value: actor),
    URLQueryItem(name: "limit", value: "100"),
    URLQueryItem(name: "filter", value: "posts_no_replies"),
  ]
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  let response = try decoder.decode(AuthorFeed.self, from: try await getData(components.url!))
  return response.feed.compactMap { FeedItem($0.post.record) }
}

private func downloadFrontPage() async throws -> [FeedItem] {
  let ids = try JSONDecoder().decode([Int].self, from: try await getData(hnAPI / "topstories.json"))
  return try await withThrowingTaskGroup(of: (Int, HNItem?).self) { group in
    for (rank, id) in ids.prefix(frontPageSize).enumerated() {
      group.addTask {
        let data = try await getData(hnAPI / "item/\(id).json")
        return (rank, try JSONDecoder().decode(HNItem?.self, from: data))
      }
    }
    var ranked: [(Int, HNItem?)] = []
    for try await result in group {
      ranked.append(result)
    }
    return ranked.sorted { $0.0 < $1.0 }.compactMap { $0.1.flatMap(FeedItem.init) }
  }
}

private func encodeFeed(_ items: [FeedItem]) throws -> Data {
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .secondsSince1970
  return try items.reduce(into: Data()) { data, item in
    data += try encoder.encode(item)
    data += Data("\n".utf8)
  }
}

private func getData(_ url: URL) async throws -> Data {
  let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
  let (data, response) = try await URLSession.shared.data(for: request)
  guard (response as? HTTPURLResponse)?.statusCode == 200 else {
    throw URLError(.badServerResponse)
  }
  return data
}

private struct AuthorFeed: Decodable {
  let feed: [Entry]

  struct Entry: Decodable {
    let post: Post
  }

  struct Post: Decodable {
    let record: Record
  }

  struct Record: Decodable {
    let text: String
    let createdAt: Date
    let facets: [Facet]?
  }

  struct Facet: Decodable {
    let index: ByteSlice
    let features: [Feature]
  }

  struct ByteSlice: Decodable {
    let byteStart: Int
  }

  struct Feature: Decodable {
    let uri: String?
  }
}

extension FeedItem {
  fileprivate init?(_ record: AuthorFeed.Record) {
    let links = (record.facets ?? [])
      .sorted { $0.index.byteStart < $1.index.byteStart }
      .compactMap { facet in
        facet.features.compactMap(\.uri).first.map { (start: facet.index.byteStart, uri: $0) }
      }
    guard let first = links.first, let id = links.last.flatMap({ hnItemId($0.uri) }) else {
      return nil
    }
    let hnlink = hnItemURL(id)
    let title = String(decoding: Data(record.text.utf8).prefix(first.start), as: UTF8.self)
    self.init(
      id: id, title: title.trimmingCharacters(in: .whitespaces),
      link: links.count > 1 ? URL(string: first.uri) ?? hnlink : hnlink, hnlink: hnlink,
      author: nil, ts: record.createdAt)
  }
}

private func hnItemId(_ link: String) -> Int? {
  URLComponents(string: link)?.queryItems?.first { $0.name == "id" }?.value.flatMap { Int($0) }
}

private func hnItemURL(_ id: Int) -> URL {
  URL(string: "https://news.ycombinator.com/item?id=\(id)")!
}

private let hnAPI = URL(string: "https://hacker-news.firebaseio.com/v0")!
private let frontPageSize = 30

private let risingFeedURL = URL(string: "https://ayroblu.github.io/hnfeed/feed.jsonl")!

private struct HNItem: Decodable {
  let id: Int
  let title: String?
  let url: URL?
  let by: String?
  let time: Int
}

extension FeedItem {
  fileprivate init?(_ item: HNItem) {
    guard let title = item.title else { return nil }
    let hnlink = hnItemURL(item.id)
    self.init(
      id: item.id, title: title, link: item.url ?? hnlink, hnlink: hnlink, author: item.by,
      ts: Date(timeIntervalSince1970: TimeInterval(item.time)))
  }
}

import Foundation
import Observation
import feed

@Observable
final class FeedModel {
  let source: FeedSource
  private(set) var items: [FeedItem] = []
  private(set) var fetchedAt: Date?
  private(set) var error: Error?
  private var isRefreshing = false

  init(source: FeedSource) {
    self.source = source
  }

  func load() async {
    if let cached = await loadCachedFeed(source) {
      apply(cached)
    }
    await refresh()
  }

  func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      apply(try await downloadFeed(source))
      error = nil
    } catch {
      self.error = error
    }
  }

  private func apply(_ feed: Feed) {
    items = feed.items
    fetchedAt = feed.fetchedAt
  }
}

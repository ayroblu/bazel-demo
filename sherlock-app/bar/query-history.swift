import Foundation

final class QueryHistory {
  private(set) var queries: [String]

  init() {
    queries = UserDefaults.standard.stringArray(forKey: Key.queries) ?? []
  }

  func record(_ query: String) {
    guard !query.allSatisfy(\.isWhitespace) else { return }
    queries.removeAll { $0 == query }
    queries.insert(query, at: 0)
    queries = Array(queries.prefix(100))
    UserDefaults.standard.set(queries, forKey: Key.queries)
  }
}

private enum Key {
  static let queries = "queryHistory"
}

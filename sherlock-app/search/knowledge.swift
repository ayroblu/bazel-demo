import Foundation

final class Knowledge {
  private var picks: [String: String]
  private var launches: [String: Int]

  init() {
    picks = UserDefaults.standard.dictionary(forKey: Key.picks) as? [String: String] ?? [:]
    launches = UserDefaults.standard.dictionary(forKey: Key.launches) as? [String: Int] ?? [:]
  }

  func boost(query: String, id: String) -> Int {
    (picks[query] == id ? 500 : 0) + min(launches[id] ?? 0, 50) * 2
  }

  func record(query: String, id: String) {
    picks[query] = id
    launches[id, default: 0] += 1
    UserDefaults.standard.set(picks, forKey: Key.picks)
    UserDefaults.standard.set(launches, forKey: Key.launches)
  }
}

private enum Key {
  static let picks = "knowledge.picks"
  static let launches = "knowledge.launches"
}

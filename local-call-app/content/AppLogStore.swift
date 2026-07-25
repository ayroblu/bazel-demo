import Log
import SwiftUI

@MainActor
final class AppLogStore: ObservableObject {
  static let shared = AppLogStore()

  @Published private(set) var lines: [String] = []

  private init() {
    registerLogEffects(effects: [
      stdoutEffect,
      { item in
        Task { @MainActor in
          AppLogStore.shared.append(item)
        }
      },
    ])
  }

  private func append(_ item: LogItem) {
    lines.append(item.getFullText())
    if lines.count > 300 {
      lines.removeFirst(lines.count - 300)
    }
  }

  func clear() {
    lines.removeAll()
  }
}

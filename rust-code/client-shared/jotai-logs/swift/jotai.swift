import Foundation
import SwiftUI
import jotai_logs

@MainActor
struct RustJotaiStoreKey: EnvironmentKey {
  static let defaultValue: RustJotaiStore = createStore()
}

extension EnvironmentValues {
  @MainActor
  public var rustJotaiStore: RustJotaiStore {
    get { self[RustJotaiStoreKey.self] }
    set { self[RustJotaiStoreKey.self] = newValue }
  }
}

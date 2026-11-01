import KVCache
import SwiftUI
import content

@main
struct MainApp: App {
  init() {
    initKvCache()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

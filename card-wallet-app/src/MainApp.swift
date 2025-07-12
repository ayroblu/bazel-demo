import SwiftUI
import models

@main
struct MainApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .modelContainer(modelContainer.value)
    }
  }
}

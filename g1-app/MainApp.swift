import Log
import SwiftData
import SwiftUI
import content

@main
struct MainApp: App {
  var body: some Scene {
    WindowGroup {
      MainView()
    }
  }
}

struct MainView: View {
  var body: some View {
    let modelContainer = getModelContainer()
    if let modelContainer {
      ContentView()
        .modelContainer(modelContainer)
    } else {
      Text("failed to get model container")
    }
  }
}

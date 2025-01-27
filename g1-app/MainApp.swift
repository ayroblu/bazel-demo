import SwiftUI

@main
struct BazelApp: App {
  var body: some Scene {
    WindowGroup {
      TabView {
        Tab("Home", systemImage: "house.fill") {
          Text("Hello from Bazel!")
        }

        Tab("Todo", systemImage: "list.bullet") {
          Text("Todo")
        }

        Tab("More todo", systemImage: "checklist.unchecked") {
          Text("More todo")
        }
      }
    }
  }
}

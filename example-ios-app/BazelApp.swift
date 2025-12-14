import SwiftLib
import SwiftUI
import drag_example
import jotai_example
import rust_uniffi_example
import sqlite_example

@main
struct BazelApp: App {
  var body: some Scene {
    WindowGroup {
      TabView {
        Tab("Home", systemImage: "house.fill") {
          Text("Hello from Bazel!")
          Text("rust add: 1 + 2 = \(SwiftRust.add(1, 2))")
          RustUniffiExampleView()
          SqliteExampleView()
        }

        Tab("Todo", systemImage: "list.bullet") {
          Text("Todo")
          JotaiExampleView()
        }

        Tab("More todo", systemImage: "checklist.unchecked") {
          Text("More todo")
          DragExampleView()
        }
      }
    }
  }
}

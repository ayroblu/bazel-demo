import FileUtils
import SwiftLib
import SwiftUI
import SwiftUIUtils
import drag_example
import jotai_example
import jotai_logs
import rust_jotai_lib
import rust_logs
import rust_uniffi_example
import sqlite_example

@main
struct BazelApp: App {
  private let store = createStore()

  private let deleteOldLogsAtom: DeleteOldLogsAtom
  init() {
    initEffects(store: store)
    self.deleteOldLogsAtom = DeleteOldLogsAtom(store: store)
    onLaunch()
  }

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

        Tab("Logs", systemImage: "info.circle.text.page") {
          NavigationLazyView {
            LogsView()
          }
        }
      }
      .environment(\.rustJotaiStore, store)
      .onAppear {
        deleteOldLogsAtom.set()
      }
    }
  }
}

func onLaunch() {
  let url =
    try! FileManager.default.url(
      for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
    ) / (Bundle.main.bundleIdentifier ?? "__unknown__")
  initLogDb(path: url.path)
}

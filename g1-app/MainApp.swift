import Log
import SwiftData
import SwiftUI
import content

@main
struct MainApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .modelContainer(for: [
      GlassesModel.self,
      NoteModel.self,
      LogEntry.self,
    ])
  }
}

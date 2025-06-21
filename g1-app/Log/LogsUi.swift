import SwiftData
import SwiftUI

public struct LogsUi: View {
  @Query(sort: \LogEntry.persistentModelID, order: .reverse) private var logItems: [LogEntry]
  @Environment(\.modelContext) private var modelContext

  public init() {}

  public var body: some View {
    List {
      if logItems.count == 0 {
        Text("No items")
      } else {
        ForEach(logItems) { logItem in
          VStack(alignment: .leading) {
            Text(logItem.text)
            Text(formatTime(from: logItem.timestamp))
              .font(.footnote)
          }
        }
      }
    }
    #if os(iOS)
      .listStyle(.grouped)
    #else
      .listStyle(.inset)
    #endif
    .navigationTitle("Logs")
    .toolbar {
      if logItems.count > 0 {
    #if os(iOS)
        let placement: ToolbarItemPlacement = .topBarTrailing
    #else
        let placement: ToolbarItemPlacement = .automatic
    #endif
        ToolbarItem(placement: placement) {
          Button(action: {
            try? deleteAll()
          }) {
            Image(systemName: "trash")
          }
        }
      }
    }
  }

  func deleteAll() throws {
    try modelContext.delete(model: LogEntry.self)
    try modelContext.save()
  }
}

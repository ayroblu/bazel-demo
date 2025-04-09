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
          Text(logItem.text)
          Text(logItem.timestamp.pretty())
            .font(.footnote)
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
        ToolbarItem(placement: .navigationBarTrailing) {
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

extension Date {
  func pretty() -> String {
    let date = self
    let formatter = DateFormatter()
    formatter.dateStyle = .medium  // e.g., "Apr 9, 2025"
    formatter.timeStyle = .short  // e.g., "3:30 PM"

    return formatter.string(from: date)
  }
}

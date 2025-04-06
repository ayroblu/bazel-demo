import SwiftData
import SwiftUI

public struct LogsUi: View {
  @Query(sort: \LogEntry.persistentModelID, order: .reverse) private var logItems: [LogEntry]

  public init() {}

  public var body: some View {
    List {
      if logItems.count == 0 {
        Text("No items")
      }
      ForEach(logItems) { logItem in
        Text(logItem.text)
      }
    }
    #if os(iOS)
      .listStyle(.grouped)
    #else
      .listStyle(.inset)
    #endif
    .navigationTitle("Logs")
  }
}

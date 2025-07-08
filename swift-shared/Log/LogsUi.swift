import SwiftData
import SwiftUI

public struct LogsUi: View {
  @Query(sort: \LogEntry.persistentModelID, order: .reverse) private var logItems: [LogEntry]
  @Environment(\.modelContext) private var modelContext

  @State private var position: ScrollPosition = .init(idType: LogEntry.ID.self)

  public init() {}

  public var body: some View {
    if logItems.count == 0 {
      Text("No items")
        .navigationTitle("Logs")
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack {
            ForEach(logItems) { logItem in
              VStack(alignment: .leading) {
                Text(logItem.text)
                HStack {
                  Spacer()
                  Text(formatTime(from: logItem.timestamp))
                    .font(.footnote)
                    .foregroundColor(.gray)
                }
              }
            }
          }
          .scrollTargetLayout()
        }
        .scrollPosition($position, anchor: .center)
        .navigationTitle("Logs")
        .toolbar {
          if logItems.count > 0 {
            ToolbarItem {
              Button("Delete", systemImage: "trash") {
                try? deleteAll()
              }
            }
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

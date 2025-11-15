import Jotai
import LogDb
import SwiftUI

public struct LogsUi: View {
  @AtomValue(selectLogsAtom) private var logItems: [LogModel]

  @State private var position: ScrollPosition = .init(idType: Int64.self)

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
                  Text(logItem.createdAt.formatTimeWithMillis())
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
    try deleteAllLogsAndInvalidate()
  }
}

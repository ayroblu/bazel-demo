import DateUtils
import SwiftUI
import jotai_logs
import rust_jotai_lib

public struct LogsView: View {
  @Environment(\.rustJotaiStore) private var rustJotaiStore: RustJotaiStore
  public init() {}
  public var body: some View {
    LogsViewInner(rustJotaiStore: rustJotaiStore)
  }
}
struct LogsViewInner: View {
  // @AtomValue(selectLogsAtom) private var logItems: [LogModel]
  @State private var logItems: [Log]

  @State private var position: ScrollPosition = .init(idType: Int64.self)
  private let logAtom: LogAtom
  private let deleteLogsAtom: DeleteLogsAtom

  init(rustJotaiStore: RustJotaiStore) {
    self.logAtom = LogAtom(store: rustJotaiStore)
    self.deleteLogsAtom = DeleteLogsAtom(store: rustJotaiStore)
    _logItems = State(wrappedValue: logAtom.get())
  }

  public var body: some View {
    NavigationStack {
      if logItems.count == 0 {
        Text("No items")
          .navigationTitle("Logs")
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack {
              ForEach(Array(logItems.enumerated()), id: \.offset) { index, logItem in
                let previous = index > 0 ? logItems[index - 1] : nil
                if let previous {
                  let interval = abs(previous.createdAt.timeIntervalSince(logItem.createdAt))
                  if interval > 60 {
                    HStack {
                      Spacer()
                      Rectangle()
                        .fill(Color.gray)
                        .frame(width: 20, height: 1)
                      Spacer()
                    }.padding(2)
                  }
                }

                ZStack(alignment: .bottomTrailing) {
                  VStack(alignment: .leading) {
                    Text(logItem.text + " " + String(repeating: "\u{00A0}", count: 21))
                      .frame(maxWidth: .infinity, alignment: .leading)
                  }
                  Text(logItem.createdAt.formatTimeWithMillis())
                    .font(.footnote)
                    .foregroundColor(.gray)
                }.padding(.horizontal)
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
                  deleteAll()
                }
              }
            }
          }
        }
      }
    }
    .navigationTitle("Logs")
    .onAppear {
      updateAndTrack()
    }
    .onDisappear {
      cleanup?.dispose()
      cleanup = nil
    }
  }

  @State var cleanup: Cleanup?
  func updateAndTrack() {
    cleanup = logAtom.sub(func: ClosureWrapper { logItems = logAtom.get() })
  }

  func deleteAll() {
    deleteLogsAtom.set()
  }
}

// @unchecked: We know that we only use this callback on the UI
final class ClosureWrapper: ClosureCallback, @unchecked Sendable {
  let callback: () -> Void

  init(_ callback: @escaping () -> Void) {
    self.callback = callback
  }

  func notif() {
    callback()
  }
}

import Jotai
import LogDb
import SwiftUI

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

public struct LogsUi: View {
  @AtomValue(selectLogsAtom) private var logItems: [LogModel]

  @State private var position: ScrollPosition = .init(idType: Int64.self)
  @State private var selecting = false
  @State private var selected: Set<Int64> = []
  @State private var drag: (base: Set<Int64>, anchor: Int64, location: CGPoint)?
  @State private var rowFrames: [Int64: CGRect] = [:]
  @State private var viewportHeight: CGFloat = 0
  @State private var autoScroll: Task<Void, Never>?

  private let space = "logs"

  public init() {}

  public var body: some View {
    if logItems.isEmpty {
      Text("No items")
        .navigationTitle("Logs")
    } else {
      ScrollView {
        LazyVStack {
          ForEach(Array(logItems.enumerated()), id: \.element.id) { index, logItem in
            if index > 0,
              abs(logItems[index - 1].createdAt.timeIntervalSince(logItem.createdAt)) > 60
            {
              Rectangle()
                .fill(Color.gray)
                .frame(width: 20, height: 1)
                .padding(2)
            }
            row(logItem)
          }
        }
        .scrollTargetLayout()
        .selectDragGesture(space: space, onChange: handleSelectDrag)
      }
      .coordinateSpace(.named(space))
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
      .scrollPosition($position, anchor: .center)
      .onChange(of: logItems.first?.id) { previousTop, _ in
        // Stable ids keep the anchored row in place as logs are inserted above it; only a
        // reader already at the top follows the newest log.
        if let previousTop, let frame = rowFrames[previousTop], frame.minY >= -1 {
          position.scrollTo(edge: .top)
        }
      }
      .navigationTitle(selecting ? "\(selected.count) selected" : "Logs")
      .toolbar {
        if selecting {
          ToolbarItem {
            Button("Copy", systemImage: "doc.on.doc") { copySelected() }
              .disabled(selected.isEmpty)
          }
          ToolbarItem {
            Button("Delete", systemImage: "trash") {
              try? deleteLogsAndInvalidate(ids: Array(selected))
              endSelecting()
            }
            .disabled(selected.isEmpty)
          }
          ToolbarItem {
            Button("Done") { endSelecting() }
          }
        } else {
          ToolbarItem {
            Button("Delete", systemImage: "trash") {
              try? deleteAllLogsAndInvalidate()
            }
          }
        }
      }
    }
  }

  private func row(_ logItem: LogModel) -> some View {
    let time = logItem.createdAt.formatTimeWithMillis()
    let isSelected = selected.contains(logItem.id)
    return ZStack(alignment: .bottomTrailing) {
      // The invisible copy reserves the timestamp's width, so a long line wraps instead of
      // running underneath it.
      (Text(logItem.text) + Text(" " + time).font(.footnote).foregroundColor(.clear))
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(time)
        .font(.footnote)
        .foregroundColor(.gray)
    }
    .padding(.horizontal)
    .overlay(alignment: .topTrailing) {
      if selecting {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected ? Color.accentColor : Color.gray)
          .padding(.trailing, 4)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      guard selecting else { return }
      if selected.remove(logItem.id) == nil {
        selected.insert(logItem.id)
      }
    }
    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: {
      rowFrames[logItem.id] = $0
    }
    .onDisappear { rowFrames[logItem.id] = nil }
  }

  private func handleSelectDrag(_ state: SelectDragState, _ point: CGPoint) {
    switch state {
    case .began:
      guard let anchor = rowId(at: point.y) else { return }
      selecting = true
      drag = (selected, anchor, point)
      extendSelection()
    case .changed:
      drag?.location = point
      extendSelection()
      updateAutoScroll(y: point.y)
    default:
      drag = nil
      autoScroll?.cancel()
      autoScroll = nil
    }
  }

  private func rowId(at y: CGFloat) -> Int64? {
    rowFrames.min { abs($0.value.midY - y) < abs($1.value.midY - y) }?.key
  }

  private func extendSelection() {
    guard let drag, let current = rowId(at: drag.location.y),
      let from = logItems.firstIndex(where: { $0.id == drag.anchor }),
      let to = logItems.firstIndex(where: { $0.id == current })
    else { return }
    selected = drag.base.union(logItems[min(from, to)...max(from, to)].map { $0.id })
  }

  private func updateAutoScroll(y: CGFloat) {
    let direction = y < 60 ? -1 : y > viewportHeight - 60 ? 1 : 0
    guard direction != 0 else {
      autoScroll?.cancel()
      autoScroll = nil
      return
    }
    guard autoScroll == nil else { return }
    autoScroll = Task { @MainActor in
      while !Task.isCancelled {
        scrollOneRow(direction: direction)
        extendSelection()
        try? await Task.sleep(for: .milliseconds(80))
      }
    }
  }

  private func scrollOneRow(direction: Int) {
    let edge =
      direction < 0
      ? rowFrames.min { $0.value.minY < $1.value.minY }
      : rowFrames.max { $0.value.maxY < $1.value.maxY }
    guard let edge, let index = logItems.firstIndex(where: { $0.id == edge.key }),
      logItems.indices.contains(index + direction)
    else { return }
    position.scrollTo(id: logItems[index + direction].id, anchor: direction < 0 ? .top : .bottom)
  }

  private func endSelecting() {
    selecting = false
    selected = []
  }

  private func copySelected() {
    let text = logItems.reversed().filter { selected.contains($0.id) }
      .map { "\($0.createdAt.formatTimeWithMillis()) \($0.text)" }
      .joined(separator: "\n")
    #if canImport(UIKit)
      UIPasteboard.general.string = text
    #else
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    #endif
    endSelecting()
  }
}

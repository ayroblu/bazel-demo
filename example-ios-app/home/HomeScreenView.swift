import SwiftUI

struct IconFramePreferenceKey: PreferenceKey {
  static var defaultValue: [UUID: CGRect] = [:]

  static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { $1 })
  }
}

struct IconItem: Identifiable, Equatable {
  let id = UUID()
  let name: String
  let systemImage: String
  let color: Color
}

public struct HomeScreenView: View {
  public init() {}
  public var body: some View {
    HomeScreenInnerView()
  }
}
struct HomeScreenInnerView: View {
  @State private var icons: [IconItem] = [
    IconItem(name: "Messages", systemImage: "bubble.left.fill", color: .green),
    IconItem(name: "Photos", systemImage: "photo.fill", color: .blue),
    IconItem(name: "Music", systemImage: "music.note", color: .red),
    IconItem(name: "Calendar", systemImage: "calendar", color: .orange),
    IconItem(name: "Camera", systemImage: "camera.fill", color: .purple),
    IconItem(name: "Weather", systemImage: "cloud.sun.fill", color: .cyan),
    IconItem(name: "Notes", systemImage: "text.document", color: .yellow),
    IconItem(name: "Maps", systemImage: "map.fill", color: .mint),
    IconItem(name: "Safari", systemImage: "safari.fill", color: .indigo),
    IconItem(name: "Settings", systemImage: "gear", color: .gray),
    IconItem(name: "Clock", systemImage: "clock.fill", color: .blue),
    IconItem(name: "Reminders", systemImage: "list.bullet", color: .orange),
  ]

  @State private var iconFrames: [UUID: CGRect] = [:]
  @State private var draggedItem: IconItem?
  @State private var initialFrame: CGRect = .zero
  @State private var currentDragTranslation: CGSize = .zero
  @State private var currentFrame: CGRect = .zero

  let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 4)

  var body: some View {
    NavigationStack {
      ScrollView {
        ZStack {
          LazyVGrid(columns: columns, spacing: 32) {
            ForEach(icons) { icon in
              IconView(icon: icon, isDragging: draggedItem?.id == icon.id)
                .background(
                  GeometryReader { geo in
                    Color.clear
                      .preference(
                        key: IconFramePreferenceKey.self,
                        value: [icon.id: geo.frame(in: .named("grid"))]
                      )
                  }
                )
                .opacity(draggedItem?.id == icon.id ? 0 : 1.0)
                .offset(offsetFor(icon))
                .gesture(
                  DragGesture(minimumDistance: 0, coordinateSpace: .named("grid"))
                    .onChanged { value in
                      if draggedItem == nil {
                        draggedItem = icon
                        if let frame = iconFrames[icon.id] {
                          initialFrame = frame
                          currentFrame = frame
                        }
                      }
                      currentDragTranslation = value.translation
                      updateLiveReordering(with: value.location)
                    }
                    .onEnded { _ in
                      withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        currentDragTranslation = .zero
                        initialFrame = currentFrame
                      } completion: {
                        initialFrame = .zero
                        currentFrame = .zero
                        draggedItem = nil
                      }
                    }
                )
            }
          }
          .padding(20)
          .coordinateSpace(name: "grid")
          if let draggedItem {
            // This is so that the item appears on top of other items
            IconView(icon: draggedItem, isDragging: true)
              .position(
                x: currentDragTranslation.width + initialFrame.midX,
                y: currentDragTranslation.height + initialFrame.midY,
              )
          }
        }
      }
      .onPreferenceChange(IconFramePreferenceKey.self) { frames in
        iconFrames = frames
      }
      .navigationTitle("Home Screen")
      .background(Color(.systemGroupedBackground))
    }
  }

  private func offsetFor(_ icon: IconItem) -> CGSize {
    guard let draggedItem, draggedItem.id == icon.id else { return .zero }

    let deltaX = currentFrame.minX - initialFrame.minX
    let deltaY = currentFrame.minY - initialFrame.minY

    return CGSize(
      width: currentDragTranslation.width - deltaX,
      height: currentDragTranslation.height - deltaY
    )
  }

  // Accurate hit testing using real frames
  private func updateLiveReordering(with dragLocation: CGPoint) {
    guard let dragged = draggedItem,
      let currentIndex = icons.firstIndex(of: dragged)
    else { return }

    // Find which icon's frame contains the current drag location
    for (index, icon) in icons.enumerated() where index != currentIndex {
      if let frame = iconFrames[icon.id], frame.contains(dragLocation) {
        if index != currentIndex {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            currentFrame = frame
            icons.move(
              fromOffsets: IndexSet(integer: currentIndex),
              toOffset: index > currentIndex ? index + 1 : index)
          }
        }
        break
      }
    }
  }
}

struct IconView: View {
  let icon: IconItem
  let isDragging: Bool

  var body: some View {
    VStack(spacing: 8) {
      ZStack {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .fill(icon.color.gradient)
          .frame(width: 78, height: 78)
          .shadow(
            color: .black.opacity(isDragging ? 0.35 : 0.2),
            radius: isDragging ? 15 : 8,
            y: isDragging ? 10 : 5)

        Image(systemName: icon.systemImage)
          .font(.system(size: 36, weight: .semibold))
          .foregroundStyle(.white)
      }
      // .scaleEffect(isDragging ? 1.18 : 1.0)

      Text(icon.name)
        .font(.caption2)
        .fontWeight(.medium)
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity)
  }
}

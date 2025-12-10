import SwiftUI

public struct DragExampleView: View {
  let item = LogItem(text: "User logged in successfully.", timestamp: "23:59:59.001")

  @State private var offset: CGFloat = 0
  @State private var lastOffset: CGFloat = 0

  let revealWidth: CGFloat = 100

  public init() {}

  public var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .trailing) {
        HStack {
          Spacer()
          Text(item.timestamp)
            .font(.footnote)
            .foregroundColor(.gray)
            .frame(width: revealWidth)
            .background(Color(.systemGroupedBackground))
        }
        .frame(width: geometry.size.width)

        VStack(alignment: .leading) {
          Text(item.text)
        }
        .frame(width: geometry.size.width, alignment: .leading)
        .padding(.horizontal)
        .background(Color.white)
        .offset(x: self.offset)
        .gesture(dragGesture())
      }
    }
    .frame(height: 50)
  }

  func dragGesture() -> some Gesture {
    DragGesture()
      .onChanged { value in
        let translation = value.translation.width
        self.offset = min(0, max(-revealWidth, lastOffset + translation))
      }
      .onEnded { value in
        withAnimation(.spring()) {
          if self.offset < -revealWidth / 2 {
            // Snap fully open
            // self.offset = -revealWidth

            self.offset = 0
          } else {
            self.offset = 0
          }
          self.lastOffset = self.offset
        }
      }
  }
}

struct LogItem: Identifiable {
  let id = UUID()
  let text: String
  let timestamp: String
}

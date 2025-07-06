import Jotai
import SwiftUI
import SwiftUIUtils

private let aspectRatio = 16 / 9
struct AddCardTileView: View {
  @AtomState(isShowAddCardSheetAtom) var isShowAddCardSheet: Bool

  var body: some View {
    Button {
      isShowAddCardSheet = true
    } label: {
      GeometryReader { geometry in
        let side = geometry.size.width
        ZStack {
          #if os(iOS)
            Rectangle()
              .fill(Color(uiColor: .secondarySystemBackground))
              .cornerRadius(10)
          #else
            Rectangle()
              .fill(Color(nsColor: .controlBackgroundColor))
              .cornerRadius(10)
          #endif
          Image(systemName: "plus.circle")
            .foregroundColor(.primary)
            .font(.title)
        }
        .frame(width: side, height: side / 16 * 9)
      }
      .aspectRatio(16 / 9, contentMode: .fit)
    }
  }
}

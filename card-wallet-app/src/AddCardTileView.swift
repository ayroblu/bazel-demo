import SwiftUI
import SwiftUIUtils
import Jotai

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
          Rectangle()
            .fill(.gray)
            .cornerRadius(10)
          Image(systemName: "plus.circle")
        }
        .frame(width: side, height: side / 16 * 9)
      }
      .aspectRatio(16 / 9, contentMode: .fit)
    }
  }
}

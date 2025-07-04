import SwiftUI

private let aspectRatio = 16 / 9
struct CardView: View {
  let card: CardModel
  var body: some View {
    GeometryReader { geometry in
      let side = geometry.size.width
      ZStack {
        Rectangle()
          .fill(.blue)
          .cornerRadius(10)
        Text(card.title)
          .foregroundColor(.white)
      }
      .frame(width: side, height: side / 16 * 9)
    }
    .aspectRatio(16 / 9, contentMode: .fit)
  }
}

import SwiftUI

struct ViewCardView: View {
  let card: CardModel
  var body: some View {
    ScrollView {
      BarcodeView(barcodeString: card.barcode)
      Text(card.barcode)
    }
    .navigationTitle(card.title)
  }
}

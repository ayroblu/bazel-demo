import Jotai
import LogUtils
import SwiftUI
import SwiftUIUtils
import models

struct EditCardView: View {
  @Bindable var card: CardModel

  var body: some View {
    List {
      Section("Card number") {
        TextField("Card number", text: $card.barcode)
      }
      Section("Card number") {
        TextField("Name", text: $card.title)
      }
    }
  }
}

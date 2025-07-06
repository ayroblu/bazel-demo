import Jotai
import SwiftData
import SwiftUI
import SwiftUIUtils

struct CardListView: View {
  @Query private var cards: [CardModel]

  let columns = [
    GridItem(.flexible()),
    GridItem(.flexible()),
  ]
  var body: some View {
    ScrollView {
      LazyVGrid(columns: columns, spacing: 10) {
        ForEach(cards) { card in
          // NavigationLink {
          //   NavigationLazyView {
          //     ViewCardView(card: card)
          //   }
          // } label: {
          //   CardView(card: card)
          // }
          NavigationLink(value: card) {
            CardView(card: card)
          }
        }
        AddCardTileView()
      }
      .navigationDestination(for: CardModel.self) { card in
        ViewCardView(card: card)
      }
      .padding()
    }
  }
}

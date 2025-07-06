import Jotai
import SwiftData
import SwiftUI
import SwiftUIUtils

struct CardListView: View {
  @Query private var cards: [CardModel]
  @State private var searchText = ""

  var filteredCards: [CardModel] {
    if searchText.isEmpty {
      return cards
    }
    let lowerSearchText = searchText.lowercased()
    return cards.filter { $0.title.lowercased().contains(lowerSearchText) }
  }

  let columns = [
    GridItem(.flexible()),
    GridItem(.flexible()),
  ]
  var body: some View {
    ScrollView {
      LazyVGrid(columns: columns, spacing: 10) {
        ForEach(filteredCards) { card in
          NavigationLink(value: card) {
            CardView(card: card)
          }
        }
        AddCardTileView()
      }
      .searchable(text: $searchText)
      .navigationDestination(for: CardModel.self) { card in
        ViewCardView(card: card)
      }
      .padding()
    }
  }
}

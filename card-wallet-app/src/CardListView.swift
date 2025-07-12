import Jotai
import Shortcuts
import SwiftData
import SwiftUI
import SwiftUIUtils
import models

struct CardListView: View {
  @Query private var cards: [CardModel]
  @State private var searchText = ""
  @AtomState(navigationPathAtom) private var path: NavigationPath
  @AtomState(startCardAtom) private var startCard: UUID?

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
      .onChange(of: startCard) { onStart() }
      .onAppear { onStart() }
      .onOpenURL { url in
        // TODO: url
        if let card = cards.first {
          path.append(card)
        }
      }
    }
  }

  private func onStart() {
    guard let startCard else { return }
    self.startCard = nil
    let first = cards.first(where: { model in model.id == startCard })
    guard let first else { return }
    path.removeLast(path.count)
    path.append(first)
  }
}

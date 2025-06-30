import SwiftUI

struct ContentView: View {
  var body: some View {
    NavigationStack {
      CardListView()
        .navigationTitle("Card Wallet View")
        .toolbar {
          ToolbarItem(placement: .automatic) {
            Button(action: {
              // Add a card
            }) {
              Image(systemName: "plus")
            }

          }
        }
    }
  }
}

#Preview {
  ContentView()
}

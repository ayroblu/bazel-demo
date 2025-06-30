import SwiftUI
import SwiftUIUtils

struct ContentView: View {
  var body: some View {
    NavigationStack {
      CardListView()
        .navigationTitle("Card Wallet")
        .toolbar {
          ToolbarItem(placement: .automatic) {
            NavigationLink {
              NavigationLazyView {
                AddCardView()
              }
            } label: {
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

import Jotai
import SwiftUI
import SwiftUIUtils

struct ContentView: View {
  @AtomState(isShowAddCardSheetAtom) private var isShowAddCardSheet: Bool
  @AtomState(navigationPathAtom) private var path: NavigationPath

  var body: some View {
    NavigationStack(path: $path) {
      CardListView()
        .navigationTitle("Card Wallet")
        .toolbar {
          ToolbarItem(placement: .automatic) {
            Button {
              isShowAddCardSheet = true
            } label: {
              Image(systemName: "plus")
            }
          }
        }
        .sheet(isPresented: $isShowAddCardSheet) {
          NavigationLazyView {
            AddCardView()
              .presentationDetents([.medium])
              .presentationDragIndicator(.visible)
          }
        }
    }
  }
}
let isShowAddCardSheetAtom = PrimitiveAtom(false)
let navigationPathAtom = PrimitiveAtom(NavigationPath())

#Preview {
  ContentView()
}

import Jotai
import LogUtils
import SwiftUI
import SwiftUIUtils

struct ViewCardView: View {
  @State private var isShowEditCardSheet: Bool = false
  @State private var isShowDeleteAlert: Bool = false
  // @State private var sheetHeight: CGFloat = 300
  @Environment(\.modelContext) private var modelContext
  @AtomState(navigationPathAtom) private var path: NavigationPath

  @Bindable var card: CardModel

  var body: some View {
    BarcodeView(barcodeString: card.barcode)
    Text(card.barcode)
    List {
      Section("notes") {
        TextField("Add notes here...", text: $card.notes, axis: .vertical)
        // .lineLimit(2...)
      }
      Section("Manage") {
        Button("Edit") {
          isShowEditCardSheet = true
        }
        .foregroundColor(.primary)
        Button("Delete", role: .destructive) {
          isShowDeleteAlert = true
        }
        .alert("Delete Item", isPresented: $isShowDeleteAlert) {
          Button("Delete", role: .destructive) {
            modelContext.delete(card)
            tryFn { try modelContext.save() }
            print("path", path.count)
            if !path.isEmpty {
              path.removeLast()
            }
          }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("Are you sure you want to delete \(card.title) card? This cannot be undone")
        }
      }
    }
    .navigationTitle(card.title)
    .sheet(isPresented: $isShowEditCardSheet) {
      NavigationLazyView {
        EditCardView(card: card)
      }
      // .readHeight($sheetHeight)
      // .presentationDetents([.height(sheetHeight)])
      .presentationDetents([.medium])
      .presentationDragIndicator(.visible)
    }
  }
}

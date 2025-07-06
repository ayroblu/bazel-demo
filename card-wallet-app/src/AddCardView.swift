import Jotai
import LogUtils
import SwiftUI
import SwiftUIUtils

struct AddCardView: View {
  @State var isManual: Bool = false
  var body: some View {
    if isManual {
      AddCardManuallyView()
        .navigationTitle("Add card manually")
    } else {
      Text("Camera + Barcode icon")
      Text("-- or --")
      Button("Enter manually") {
        isManual = true
      }
      .buttonStyle(.bordered)
    }
  }
}

struct AddCardManuallyView: View {
  @Environment(\.modelContext) private var modelContext
  @State var barcode: String = ""
  @State var name: String = ""
  @AtomState(isShowAddCardSheetAtom) private var isShowAddCardSheet: Bool

  var body: some View {
    List {
      Section("Card number") {
        TextField("123456789", text: $barcode)
      }
      Section("Name") {
        TextField("Supermarket Rewards", text: $name)
      }
    }
    Button("Add") {
      modelContext.insert(CardModel(title: name, barcode: barcode))
      tryFn { try modelContext.save() }
      isShowAddCardSheet = false
    }
    .buttonStyle(.bordered)
  }
}

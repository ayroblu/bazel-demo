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

  @State var isLandscape: Bool = false

  var body: some View {
    List {
      VStack {
        Button {
          withoutAnimation {
            isLandscape = true
          }
        } label: {
          BarcodeView(barcodeString: card.barcode)
            .listRowInsets(.init())
        }
        Text(card.barcodePretty)
      }
      .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0))
      // .listRowBackground(Color.clear)
      Section("notes") {
        TextField("Add notes here...", text: $card.notes, axis: .vertical)
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
    .scrollDismissesKeyboard(.immediately)
    .navigationTitle(card.title)
    #if os(iOS)
      .fullScreenCover(isPresented: $isLandscape) {
        GeometryReader { geometry in
          let width = geometry.size.width
          let height = geometry.size.height
          FullBrightnessView()
          BarcodeView(barcodeString: card.barcode)
          .rotationEffect(.degrees(90), anchor: .topLeading)
          .offset(x: width, y: 0)
          .onTapGesture {
            withoutAnimation {
              isLandscape = false
            }
          }
          .frame(width: height, height: width)
        }
      }
    #endif
    .sheet(isPresented: $isShowEditCardSheet) {
      NavigationLazyView {
        EditCardView(card: card)
      }
      // .readHeight($sheetHeight)
      // .presentationDetents([.height(sheetHeight)])
      .presentationDetents([.medium])
      .presentationDragIndicator(.visible)
    }
    // }
  }
}

extension View {
  func withoutAnimation(action: @escaping () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      action()
    }
  }
}

struct FullBrightnessView: View {
  #if os(iOS)
    @State private var originalBrightness: CGFloat = UIScreen.main.brightness

    var body: some View {
      Color.clear
        .frame(width: 0, height: 0)
        .onAppear {
          originalBrightness = UIScreen.main.brightness
          UIScreen.main.brightness = 1.0
        }
        .onDisappear {
          UIScreen.main.brightness = originalBrightness
        }
    }
  #else
    var body: some View {
      EmptyView()
    }
  #endif
}

extension CardModel {
  var barcodePretty: String {
    var result = ""
    for (index, char) in self.barcode.enumerated() {
      if index > 0 && index % 3 == 0 {
        result += " "
      }
      result += String(char)
    }
    return result
  }
}

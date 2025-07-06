import BarcodeScanner
import Jotai
import LogUtils
import PhotosUI
import SwiftUI
import SwiftUIUtils

struct AddCardView: View {
  @Environment(\.modelContext) private var modelContext
  @State var isShowCamera: Bool = false
  @AtomState(isShowAddCardSheetAtom) private var isShowAddCardSheet: Bool
  @State var card = CardModel(title: "", barcode: "")
  @AtomState(navigationPathAtom) private var path: NavigationPath

  var body: some View {
    List {
      Button("Open camera", systemImage: "camera") {
        isShowCamera = true
      }
      PhotoBarcodeScanner(card: $card)
      Section("Card number") {
        TextField("123456789", text: $card.barcode)
      }
      Section("Name") {
        TextField("Supermarket Rewards", text: $card.title)
      }
    }
    #if os(iOS)
      .fullScreenCover(isPresented: $isShowCamera) {
        ZStack {
          CameraScannerView { scanned in
            card.barcode = scanned.barcode
            card.isQr = scanned.type == .qr
            isShowCamera = false
          }
          .edgesIgnoringSafeArea(.all)
          RoundedRectangle(cornerRadius: 20)
          .stroke(.white, lineWidth: 2)
          .frame(maxWidth: .infinity)
          .frame(height: 250)
          .padding()
        }
        .onTapGesture {
          isShowCamera = false
        }
      }
    #endif
    Button("Add") {
      modelContext.insert(card)
      tryFn { try modelContext.save() }
      isShowAddCardSheet = false
      path.append(card)
    }
    .buttonStyle(.bordered)
  }
}

struct PhotoBarcodeScanner: View {
  @State private var photoPickerItem: PhotosPickerItem?
  @Binding var card: CardModel

  var body: some View {
    PhotosPicker(selection: $photoPickerItem, matching: .images) {
      Label("From photo library", systemImage: "photo.on.rectangle.angled")
      // .font(.title2)
      // .padding()
      // .background(Color.blue)
      // .foregroundColor(.white)
      // .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    .onChange(of: photoPickerItem) { _, newItem in
      Task {
        // Load selected image
        if let data = try? await newItem?.loadTransferable(type: Data.self),
          let uiImage = UIImage(data: data)
        {
          if let scannedBarcode = try? scanImageForBarcode(image: uiImage) {
            card.barcode = scannedBarcode.barcode
            card.isQr = scannedBarcode.type == .qr
          }
        }
      }
    }
  }
}

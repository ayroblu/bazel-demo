import PhotosUI
import SwiftUI
import Vision

struct BarcodeScannerView: View {
  @State private var selectedImage: UIImage?
  @State private var detectedCode: String?
  @State private var photoPickerItem: PhotosPickerItem?

  var body: some View {
    VStack(spacing: 20) {
      // Display selected image if available
      if let image = selectedImage {
        #if os(macOS)
          Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 300)
        #else
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 300)
        #endif
      }

      // Display detected barcode/QR code
      if let code = detectedCode {
        Text("Detected Code: \(code)")
          .font(.headline)
          .padding()
      } else {
        Text("No code detected")
          .font(.headline)
          .foregroundColor(.gray)
      }

      // Photo picker button
      PhotosPicker(
        selection: $photoPickerItem,
        matching: .images
      ) {
        Label("Select Photo", systemImage: "photo")
          .font(.title2)
          .padding()
          .background(Color.blue)
          .foregroundColor(.white)
          .clipShape(RoundedRectangle(cornerRadius: 10))
      }
    }
    .padding()
    .onChange(of: photoPickerItem) { _, newItem in
      Task {
        // Load selected image
        if let data = try? await newItem?.loadTransferable(type: Data.self),
          let uiImage = UIImage(data: data)
        {
          selectedImage = uiImage
          scanImageForBarcode(image: uiImage)
        }
      }
    }
  }

  private func scanImageForBarcode(image: UIImage) {
    guard let cgImage = image.cgImage else { return }

    // Create Vision barcode request
    let request = VNDetectBarcodesRequest { request, error in
      if let error = error {
        print("Barcode scanning error: \(error)")
        return
      }

      // Process results
      guard let results = request.results as? [VNBarcodeObservation] else { return }

      // Get first detected barcode/QR code
      if let firstResult = results.first,
        let payload = firstResult.payloadStringValue
      {
        detectedCode = payload
        print("Detected code: \(payload)")
      } else {
        detectedCode = nil
      }
    }

    // Support common barcode and QR code formats
    request.symbologies = [.qr, .code128, .ean13, .upce, .code39, .pdf417]

    // Perform the request
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
    } catch {
      print("Failed to perform barcode scan: \(error)")
    }
  }
}

import CoreImage.CIFilterBuiltins
import SwiftUI

struct BarcodeView: View {
  let barcodeString: String
  private let context = CIContext()
  private let filter = CIFilter.code128BarcodeGenerator()

  var body: some View {
    if let barcodeImage = generateBarcode(from: barcodeString) {
      Image(uiImage: barcodeImage)
        .interpolation(.none)
        .resizable()
        .scaledToFit()
    } else {
      Text("Failed to generate barcode")
        .foregroundColor(.red)
    }
  }

  func generateBarcode(from string: String) -> UIImage? {
    let data = Data(string.utf8)
    filter.message = data

    if let outputImage = filter.outputImage {
      // Scale the barcode image up
      let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: 3, y: 3))
      if let cgImage = context.createCGImage(transformed, from: transformed.extent) {
        return UIImage(cgImage: cgImage)
      }
    }
    return nil
  }
}

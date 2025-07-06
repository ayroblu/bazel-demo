import CoreImage.CIFilterBuiltins
import SwiftUI

struct BarcodeView: View {
  let barcodeString: String
  private let context = CIContext()
  private let filter = CIFilter.code128BarcodeGenerator()

  var body: some View {
    if let barcodeImage = generateBarcode(from: barcodeString) {
      #if os(macOS)
        Image(nsImage: barcodeImage)
          .interpolation(.none)
          .resizable()
          .scaledToFit()
      #else
        Image(uiImage: barcodeImage)
          .interpolation(.none)
          .resizable()
          .scaledToFit()
      #endif
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
        #if os(iOS)
          return UIImage(cgImage: cgImage)
        #else
          let logicalSize = NSSize(
            width: outputImage.extent.width, height: outputImage.extent.height)
          return NSImage(cgImage: cgImage, size: logicalSize)
        #endif
      }
    }
    return nil
  }
}

#if os(macOS)
  import Cocoa

  // Step 1: Typealias UIImage to NSImage
  typealias UIImage = NSImage

  // Step 2: You might want to add these APIs that UIImage has but NSImage doesn't.
  extension NSImage {
    var cgImage: CGImage? {
      var proposedRect = CGRect(origin: .zero, size: size)

      return cgImage(
        forProposedRect: &proposedRect,
        context: nil,
        hints: nil)
    }

    // convenience init?(named name: String) {
    //   self.init(named: Name(name))
    // }
  }
#endif

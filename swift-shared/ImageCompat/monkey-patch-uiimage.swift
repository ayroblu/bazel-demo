#if os(macOS)
  import Cocoa
  import SwiftUI

  // Step 1: Typealias UIImage to NSImage
  public typealias UIImage = NSImage

  // Step 2: You might want to add these APIs that UIImage has but NSImage doesn't.
  extension NSImage {
    public var cgImage: CGImage? {
      var proposedRect = CGRect(origin: .zero, size: size)

      return cgImage(
        forProposedRect: &proposedRect,
        context: nil,
        hints: nil)
    }

    public convenience init(cgImage: CGImage, _ outputImage: CIImage) {
      let logicalSize = NSSize(
        width: outputImage.extent.width, height: outputImage.extent.height)
      self.init(cgImage: cgImage, size: logicalSize)
    }

    // convenience init?(named name: String) {
    //   self.init(named: Name(name))
    // }

    public func pngData() -> Data? {
      guard let tiffData = self.tiffRepresentation,
        let bitmapImage = NSBitmapImageRep(data: tiffData)
      else {
        return nil
      }

      return bitmapImage.representation(using: .png, properties: [:])
    }
  }
  extension Image {
    public init(uiImage: UIImage) {
      self.init(nsImage: uiImage)
    }
  }
#endif

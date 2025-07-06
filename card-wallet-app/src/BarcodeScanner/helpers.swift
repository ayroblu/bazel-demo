import PhotosUI
import SwiftUI
import Vision

public func scanImageForBarcode(image: UIImage) throws -> BarcodeResult? {
  guard let cgImage = image.cgImage else { return nil }

  let request = VNDetectBarcodesRequest()
  request.symbologies = [.qr, .code128, .ean13, .upce, .code39, .pdf417]

  let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
  try handler.perform([request])
  guard let result = request.results?.first else { return nil }
  guard let barcode = result.payloadStringValue else { return nil }
  return BarcodeResult(barcode: barcode, type: result.symbology)
}

public struct BarcodeResult {
  public let barcode: String
  public let type: VNBarcodeSymbology
}

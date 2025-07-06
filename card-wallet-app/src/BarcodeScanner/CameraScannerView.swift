import SwiftUI
import AVFoundation

public struct CameraScannerResult {
  public let barcode: String
  public let type: AVMetadataObject.ObjectType
}
public struct CameraScannerView: View {
  let completion: (CameraScannerResult) -> Void

  public init(completion: @escaping (CameraScannerResult) -> Void) {
    self.completion = completion
  }

  public var body: some View {
    BarcodeScannerView(completion: completion)
  }
}
struct BarcodeScannerView: UIViewControllerRepresentable {
  class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var parent: BarcodeScannerView

    init(parent: BarcodeScannerView) {
      self.parent = parent
    }

    func metadataOutput(
      _ output: AVCaptureMetadataOutput,
      didOutput metadataObjects: [AVMetadataObject],
      from connection: AVCaptureConnection
    ) {
      if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
        let scannedString = metadataObject.stringValue
      {
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        parent.completion(CameraScannerResult(barcode: scannedString, type: metadataObject.type))
      }
    }
  }

  var completion: (CameraScannerResult) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIViewController(context: Context) -> UIViewController {
    let viewController = UIViewController()
    let session = AVCaptureSession()
    guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
      let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
      session.canAddInput(videoInput)
    else {
      return viewController
    }

    session.addInput(videoInput)

    let metadataOutput = AVCaptureMetadataOutput()
    if session.canAddOutput(metadataOutput) {
      session.addOutput(metadataOutput)

      metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: DispatchQueue.main)
      metadataOutput.metadataObjectTypes = [.qr, .code128, .ean13, .upce, .code39, .pdf417]
    }

    let previewLayer = AVCaptureVideoPreviewLayer(session: session)
    previewLayer.frame = viewController.view.layer.bounds
    previewLayer.videoGravity = .resizeAspectFill
    viewController.view.layer.addSublayer(previewLayer)

    session.startRunning()

    return viewController
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

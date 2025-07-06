import PassKit
import SwiftUI

struct AddToWalletButton: UIViewRepresentable {
  func makeUIView(context: Context) -> PKAddPassButton {
    let button = PKAddPassButton(addPassButtonStyle: .black)  // or .white or .whiteOutline
    return button
  }

  func updateUIView(_ uiView: PKAddPassButton, context: Context) {
    // No dynamic updates needed
  }
}

struct AddPassesViewController: UIViewControllerRepresentable {
  let pass: PKPass

  func makeUIViewController(context: Context) -> PKAddPassesViewController {
    return PKAddPassesViewController(pass: pass)!
  }

  func updateUIViewController(_ uiViewController: PKAddPassesViewController, context: Context) {
    // No update needed
  }
}

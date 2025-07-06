import SwiftUI
import UIKit

struct ContentView: View {
  var body: some View {
    Text("example")
      .supportedInterfaceOrientations(.landscapeLeft)
  }
}

@main
struct MainApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

// https://stackoverflow.com/questions/75270101/swiftui-force-device-rotation-programmatically/78649939#78649939
// https://stackoverflow.com/a/78649939
class AppDelegate: NSObject, UIApplicationDelegate {
  static var supportedInterfaceOrientations = UIInterfaceOrientationMask.portrait {
    didSet { updateSupportedInterfaceOrientationsInUI() }
  }
}
extension AppDelegate {
  private static func updateSupportedInterfaceOrientationsInUI() {
    UIApplication.shared.connectedScenes.forEach { scene in
      if let windowScene = scene as? UIWindowScene {
        windowScene.requestGeometryUpdate(
          .iOS(interfaceOrientations: supportedInterfaceOrientations)
        )
      }
    }
    // UIViewController.attemptRotationToDeviceOrientation()
    UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }
      .first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
  }

  func application(
    _ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    Self.supportedInterfaceOrientations
  }
}

extension View {
  @ViewBuilder func supportedInterfaceOrientations(
    _ orientations: UIInterfaceOrientationMask
  ) -> some View {
    modifier(SupportedInterfaceOrientationsModifier(orientations: orientations))
  }
}

private struct SupportedInterfaceOrientationsModifier: ViewModifier {
  let orientations: UIInterfaceOrientationMask

  @State private var previousOrientations = UIInterfaceOrientationMask.portrait

  func body(content: Content) -> some View {
    content
      .onAppear {
        previousOrientations = AppDelegate.supportedInterfaceOrientations
        AppDelegate.supportedInterfaceOrientations = orientations
      }
      .onDisappear {
        AppDelegate.supportedInterfaceOrientations = previousOrientations
      }
  }
}

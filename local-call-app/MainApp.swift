import SwiftUI
import UIKit
import content

@main
struct MainApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

/// Bluetooth has to be set up during launch, otherwise the system will not
/// relaunch the app in the background when a paired device rings it.
class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    startConnectServices()
    return true
  }
}

import SwiftUI

@main
struct MainApp: App {
  @State private var model = ProxyModel()

  var body: some Scene {
    Window("NetProx", id: "main") {
      ContentView(model: model)
    }
  }
}

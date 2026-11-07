import SwiftUI

@main
struct MainApp: App {
  @State private var proxy = WifiProxy()

  var body: some Scene {
    MenuBarExtra {
      ProxyMenu(proxy: proxy)
    } label: {
      Image(systemName: proxy.enabled ? "network" : "network.slash")
    }
    .menuBarExtraStyle(.window)
  }
}

struct ProxyMenu: View {
  @Bindable var proxy: WifiProxy

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Toggle("Wi-Fi proxy", isOn: Binding(get: { proxy.enabled }, set: { proxy.set($0) }))
        .toggleStyle(.switch)
      TextField("host:port", text: $proxy.value)
        .onSubmit { if proxy.enabled { proxy.set(true) } }
      if let error = proxy.error {
        Text(error).foregroundStyle(.red)
      }
      Divider()
      Button("Quit") { NSApp.terminate(nil) }
    }
    .padding()
    .frame(width: 240)
    .onAppear { proxy.refresh() }
  }
}

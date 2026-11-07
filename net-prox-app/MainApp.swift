import NetworkExtension
import SwiftUI

@main
struct MainApp: App {
  @State private var proxy = VPNProxy()

  var body: some Scene {
    WindowGroup {
      ContentView(proxy: proxy)
    }
  }
}

struct ContentView: View {
  @Bindable var proxy: VPNProxy

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Toggle("Proxy", isOn: Binding(get: { proxy.enabled }, set: { proxy.set($0) }))
          TextField("host:port", text: $proxy.value)
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit { if proxy.enabled { proxy.set(true) } }
        } footer: {
          Text("Sends HTTP and HTTPS traffic through the proxy, e.g. NetProx on your Mac.")
        }
        Section {
          LabeledContent("Status", value: label(proxy.status))
          if let error = proxy.error {
            Text(error).foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("NetProx Toggle")
    }
  }
}

private func label(_ status: NEVPNStatus) -> String {
  switch status {
  case .invalid: "Not set up"
  case .disconnected: "Off"
  case .connecting: "Connecting…"
  case .connected: "On"
  case .reasserting: "Updating…"
  case .disconnecting: "Turning off…"
  @unknown default: "Unknown"
  }
}

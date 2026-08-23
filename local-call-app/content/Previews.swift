import SwiftUI

#Preview("Content") {
  ContentView()
}

#Preview("Lobby") {
  NavigationStack {
    LobbyView(vm: CallViewModel())
      .navigationTitle("Local Call")
  }
}

#Preview("In Call") {
  NavigationStack {
    InCallView(vm: CallViewModel())
      .navigationTitle("In Call")
  }
}

// Xcode previews re-execute the #Preview body with a JIT that miscompiles
// imperative statements mutating @Published properties (the preview agent
// segfaults in Combine), so the setup lives in a compiled function and the
// body stays a single expression.
@MainActor
private func makeInCallWithDevicesVM() -> CallViewModel {
  let vm = CallViewModel()
  vm.routes.inputOptions = [
    AudioOption(id: "builtin-mic", name: "iPhone Microphone"),
    AudioOption(id: "airpods-mic", name: "Your AirPods Pro"),
  ]
  vm.routes.currentInputID = "airpods-mic"
  vm.routes.outputOptions = [
    AudioOption(id: "automatic", name: "Your AirPods Pro"),
    AudioOption(id: "speaker", name: "Speaker"),
  ]
  vm.routes.currentOutputID = "automatic"
  vm.inputLevel = 0.6
  vm.outputLevel = 0.3
  return vm
}

#Preview("In Call 2") {
  NavigationStack {
    InCallView(vm: makeInCallWithDevicesVM())
      .navigationTitle("In Call")
  }
}

#Preview("Logs") {
  NavigationStack {
    LogsView(logs: AppLogStore.shared)
  }
}

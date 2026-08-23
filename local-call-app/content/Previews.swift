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

#Preview("Logs") {
  NavigationStack {
    LogsView(logs: AppLogStore.shared)
  }
}

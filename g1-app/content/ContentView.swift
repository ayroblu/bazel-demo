import Connect
import SwiftUI

public struct ContentView: View {
  @ObservedObject var vm = MainVM()
  public init() {}
  public var body: some View {
    TabView {
      Tab("Home", systemImage: "house.fill") {
        Text("Hello from Bazel!")
        Button("List") {
          vm.list()
        }
        ForEach(Array(vm.devices.enumerated()), id: \.offset) { index, device in
          Text(device)
        }
        Button("Disconnect") {
          vm.disconnect()
        }
        Button("Connect") {
          vm.connect()
        }
      }

      Tab("Todo", systemImage: "list.bullet") {
        Text("Todo")
      }

      Tab("More todo", systemImage: "checklist.unchecked") {
        Text("More todo")
      }
    }
  }
}

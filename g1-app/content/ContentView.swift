import SwiftUI

public struct ContentView: View {
  @StateObject var vm = MainVM()
  public init() {}
  public var body: some View {
    TabView {
      Tab("Home", systemImage: "house.fill") {
        NavigationView {
          VStack {
            Text("Hello from Bazel!")
            Button("List") {
              vm.list()
            }
            .buttonStyle(.borderedProminent)
            .onAppear {
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                vm.list()
              }
            }
            ForEach(Array(vm.devices.enumerated()), id: \.offset) { index, device in
              Text(device)
            }
            if vm.devices.count > 0 {
              Button("Disconnect") {
                vm.disconnect()
              }

              TextEditor(
                text: $vm.text, selection: $vm.selection
              )
              .padding().textFieldStyle(.roundedBorder)
              .frame(height: 100)

              Button("Dash Config") {
                vm.dashConfig()
              }
              .buttonStyle(.bordered)

              NavigationLink(destination: NavigateView(vm: vm)) {
                Text("Navigate")
              }
              .buttonStyle(.bordered)

              Button("Send Image") {
                vm.sendImage()
              }
              .buttonStyle(.bordered)

              Button("Send notification") {
                vm.sendNotif()
              }
              .buttonStyle(.bordered)

              Button("Listen") {
                vm.listenAudio()
              }
              .buttonStyle(.bordered)
            }
            Button("Connect") {
              vm.connect()
            }
            .buttonStyle(.bordered)
            .padding(.top)
          }
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

#Preview {
    ContentView()
}

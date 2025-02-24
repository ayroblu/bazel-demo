import SwiftUI

public struct ContentView: View {
  @StateObject var vm = MainVM()
  private let audioManager = AudioManager()
  @State private var showShareSheet = false

  public init() {}

  public var body: some View {
    TabView {
      Tab("Home", systemImage: "house.fill") {
        NavigationStack {
          List {
            GlassesInfoView(mainVm: vm)
              .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                  vm.list()
                }
              }
            HStack {
              Button("Silent Mode", systemImage: vm.silentMode ? "moon.circle.fill" : "moon.circle")
              {
                vm.connectionManager.toggleSilentMode()
              }
              .lineLimit(1)
              .layoutPriority(1)
              .foregroundStyle(.primary)
              .buttonStyle(.bordered)

            }
            let brightness = Binding(
              get: { Double(vm.brightness) },
              set: { vm.brightness = UInt8($0) }
            )
            Group {
              Slider(
                value: brightness,
                in: 0...42,
                step: 1,
                label: { Text("Brightness") },
                minimumValueLabel: {
                  Image(systemName: "sun.min").opacity(vm.autoBrightness ? 0.5 : 1)
                },
                maximumValueLabel: {
                  Image(systemName: "sun.max.fill").opacity(vm.autoBrightness ? 0.5 : 1)
                }
              ) { editing in
                if !editing {
                  vm.connectionManager.sendBrightness()
                }
              }.disabled(vm.autoBrightness)
            }
            .contentShape(Rectangle())
            .onTapGesture {
              vm.autoBrightness.toggle()
              vm.connectionManager.sendBrightness()
            }
            NavigationLink("Text Editor") {
              TextEditor(
                text: $vm.text, selection: $vm.selection
              )
              .padding().textFieldStyle(.roundedBorder)
              .frame(height: 100)
              .scrollContentBackground(.hidden)
              .background(Color(red: 0.1, green: 0.1, blue: 0.1))
            }
            NavigationLink("Dash Config") {
              Button("Dash position") {
                vm.connectionManager.dashPosition()
              }
              .buttonStyle(.bordered)
              Button("Dash notes") {
                vm.connectionManager.dashNotes()
              }
              .buttonStyle(.bordered)
              Button("Dash calendar") {
                vm.connectionManager.dashCalendar()
              }
              .buttonStyle(.bordered)
            }
            NavigationLink("Navigate") {
              NavigateView(vm: vm)
            }
            NavigationLink("Notifications") {
              Button("Send notification") {
                vm.sendNotif()
              }
              .buttonStyle(.bordered)
            }
            NavigationLink("Demo") {
              Button("Send Image") {
                vm.sendImage()
              }
              .buttonStyle(.bordered)
            }
            NavigationLink("Listen") {
              Button("Listen") {
                vm.connectionManager.listenAudio()
              }
              .buttonStyle(.bordered)
              Button("Play") {
                audioManager.listen()
              }
              .buttonStyle(.bordered)
              ShareLink("todo", item: audioManager.outputUrl)
            }
          }
        }
      }

      Tab("Todo", systemImage: "list.bullet") {
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
                vm.connectionManager.dashPosition()
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
                vm.connectionManager.listenAudio()
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

      Tab("More todo", systemImage: "checklist.unchecked") {
        Text("More todo")
      }
    }
  }
}

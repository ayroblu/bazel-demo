import CoreBluetooth
import Log
import SwiftData
import SwiftUI

public struct ContentView: View {
  @StateObject var vm = MainVM()
  @Environment(\.scenePhase) var scenePhase
  private let audioManager = AudioManager()
  @State private var showShareSheet = false
  @Query private var allGlasses: [GlassesModel]
  private var glasses: GlassesModel? { allGlasses.first }
  @Environment(\.modelContext) private var modelContext

  public init() {}

  public var body: some View {
    if CBCentralManager.authorization != .allowedAlways {
      Button("Enable bluetooth to use this app") {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      }
      .buttonStyle(.borderedProminent)
    } else if let glasses {
      NavigationStack {
        List {
          GlassesInfoView(mainVm: vm)
            .onChange(of: scenePhase) { oldPhase, newPhase in
              if newPhase == .active {
                log("syncKnown")
                vm.connectionManager.syncKnown(glasses: glasses)
              } else if newPhase == .inactive {
                log("Inactive")
              } else if newPhase == .background {
                log("Background")
              }
            }
          HStack {
            Button(
              "Silent Mode", systemImage: vm.silentMode ? "moon.circle.fill" : "moon.circle"
            ) {
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
          let autoBrightness = Binding(
            get: { vm.autoBrightness },
            set: {
              vm.autoBrightness = $0
              vm.connectionManager.sendBrightness()
            })
          Toggle(isOn: autoBrightness) {
            Text("Auto brightness")
          }
          if !vm.autoBrightness {
            Slider(
              value: brightness,
              in: 0...42,
              step: 1,
              label: { Text("Brightness") },
              minimumValueLabel: {
                Image(systemName: "sun.min")
              },
              maximumValueLabel: {
                Image(systemName: "sun.max.fill")
              }
            ) { editing in
              if !editing {
                vm.connectionManager.sendBrightness()
              }
            }
          }
          NavigationLink("Dash Config") {
            LazyView {
              DashConfigView(vm: vm)
            }
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
          NavigationLink("Navigate test") {
            List {
              Button("test") {
                vm.connectionManager.sendTestNavigate()
              }
              .buttonStyle(.bordered)
            }
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
            ShareLink("Export", item: audioManager.outputUrl)
          }
          #if DEBUG
            NavigationLink("Logs") {
              LogsUi()
            }
          #endif
        }
      }
      .onAppear {
        #if DEBUG
          initLogDb(modelContext)
        #endif
      }
    } else {
      if vm.isBluetoothEnabled {
        Text("Searching...")
          .onAppear {
            vm.connectionManager.syncUnknown(modelContext: modelContext)
          }
          .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
              log("Active")
            } else if newPhase == .inactive {
              log("Inactive")
            } else if newPhase == .background {
              log("Background")
              vm.connectionManager.stopPairing()
            }
          }
      } else {
        Text("Please enable bluetooth")
      }
    }
  }
}

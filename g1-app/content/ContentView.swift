import CoreBluetooth
import Log
import SwiftData
import SwiftUI
import g1protocol
import Jotai

let brightnessDoubleAtom = DoubleUInt8CastAtom(atom: brightnessAtom)
let autoBrightnessActAtom = WritableAtom(
  { getter in getter.get(atom: autoBrightnessAtom) },
  { (setter, newValue) in
    setter.set(atom: autoBrightnessAtom, value: newValue)
    manager.sendBrightness()
  })

public struct ContentView: View {
  @StateObject var vm = MainVM()
  @Environment(\.scenePhase) var scenePhase
  private let audioManager = AudioManager()
  @State private var showShareSheet = false
  @Query private var allGlasses: [GlassesModel]
  private var glasses: GlassesModel? { allGlasses.first }
  @Environment(\.modelContext) private var modelContext
  @AtomState(silentModeAtom) var silentMode: Bool
  @AtomState(brightnessAtom) var brightness: UInt8
  @AtomState(brightnessDoubleAtom) var brightnessDouble: Double
  @AtomState(autoBrightnessAtom) var autoBrightness: Bool
  @AtomState(isBluetoothEnabledAtom) var isBluetoothEnabled: Bool

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
          GlassesInfoView(glasses: glasses)
            .onChange(of: scenePhase) { oldPhase, newPhase in
              if newPhase == .active {
                log("Active: syncKnown")
                bluetoothManager.syncKnown(glasses: (glasses.left, glasses.right))
              } else if newPhase == .inactive {
                log("Inactive")
              } else if newPhase == .background {
                log("Background")
              }
            }
          HStack {
            Button(
              "Silent Mode", systemImage: silentMode ? "moon.circle.fill" : "moon.circle"
            ) {
              manager.toggleSilentMode()
            }
            .lineLimit(1)
            .layoutPriority(1)
            .foregroundStyle(.primary)
            .buttonStyle(.bordered)

          }
          Toggle(isOn: $autoBrightness) {
            Text("Auto brightness")
          }
          if !autoBrightness {
            Slider(
              value: $brightnessDouble,
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
                manager.sendBrightness()
              }
            }
          }
          NavigationLink("Dash Config") {
            NavigationLazyView {
              DashConfigView()
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
          NavigationLink("Navigate") {
            NavigationLazyView {
              NavigateSearchView(vm: vm)
            }
          }
          NavigationLink("Teleprompt") {
            NavigationLazyView {
              Teleprompt()
            }
          }
          // NavigationLink("Navigate") {
          //   NavigationLazyView {
          //     NavigateView(vm: vm)
          //   }
          // }
          NavigationLink("Demo") {
            Button("Send Image") {
              manager.sendImage()
            }
            .buttonStyle(.bordered)
          }
          NavigationLink("Listen") {
            Button("Listen") {
              manager.listenAudio()
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
              NavigationLazyView {
                LogsUi()
              }
            }
          #endif
        }
      }
      .onAppear {
        manager.glasses = glasses
        print(WatchConnectivityManager.shared)
        #if DEBUG
          initLogDb(modelContext)
        #endif
      }
    } else {
      if isBluetoothEnabled {
        Text("Searching...")
          .onAppear {
            bluetoothManager.syncUnknown()
          }
          .onDisappear {
            bluetoothManager.stopPairing()
          }
          .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
              log("Active")
            } else if newPhase == .inactive {
              log("Inactive")
            } else if newPhase == .background {
              log("Background")
              bluetoothManager.stopPairing()
            }
          }
      } else {
        Text("Please enable bluetooth")
      }
    }
  }
}

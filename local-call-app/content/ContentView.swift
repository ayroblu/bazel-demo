import Log
import LogDb
import LogUi
import SwiftUI
import audio
import connect
import transport

private var didStartConnectServices = false

/// Called from the app delegate, including a launch into the background
/// triggered by a paired device ringing us over bluetooth.
public func startConnectServices() {
  guard !isRunningInPreview, !didStartConnectServices else { return }
  didStartConnectServices = true
  initLogDb()
  registerLogEffects(effects: [stdoutEffect, logAtomEffect])
  CallViewModel.shared.startConnectServices()
}

public struct ContentView: View {
  @State private var vm = CallViewModel.shared
  @State private var connect = ConnectManager.shared
  @Environment(\.scenePhase) private var scenePhase

  public init() {}

  public var body: some View {
    NavigationStack {
      Group {
        if vm.isInCall, !connect.state.isRinging {
          InCallView(vm: vm)
        } else {
          LobbyView(vm: vm)
        }
      }
      .navigationTitle(connect.state.isRinging ? "Calling" : vm.isInCall ? "In Call" : "Local Call")
      .toolbar {
        NavigationLink {
          LogsUi()
        } label: {
          Label("Logs", systemImage: "doc.text.magnifyingglass")
        }
      }
    }
    .task {
      // Mic permission crashes XCPreviewAgent (its Info.plist lacks the
      // required usage descriptions)
      guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
        return
      }
      startConnectServices()
      vm.setConnectScanning(true)
      await vm.requestMicPermission()
    }
    .onChange(of: scenePhase) { _, phase in
      log("scene phase", String(describing: phase), vm.transport.callStateSummary())
      switch phase {
      case .background:
        vm.transport.handleDidEnterBackground()
        vm.setConnectScanning(false)
      case .active:
        vm.setConnectScanning(true)
        vm.resumeAudioIfStopped()
      default:
        break
      }
    }
    .callSilencedAlert(connect)
  }
}

struct LobbyView: View {
  let vm: CallViewModel
  let transport: PeerTransport
  let routes: AudioRouteController
  let connect: ConnectManager
  @State private var renamingPeer: PairedPeer?

  init(vm: CallViewModel) {
    self.vm = vm
    self.transport = vm.transport
    self.routes = vm.routes
    self.connect = vm.connect
  }

  var body: some View {
    List {
      if vm.micPermissionDenied {
        Section {
          Label(
            "Microphone access is denied, enable it in Settings to make calls",
            systemImage: "mic.slash")
          .foregroundStyle(.red)
        }
      }
      ConnectSections(connect: connect, renaming: $renamingPeer)
      if let status = transport.statusMessage {
        Section {
          Text(status)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      if vm.isTestingMic {
        Section("Mic test") {
          AudioDevicePicker(
            title: "Microphone", systemImage: "mic",
            options: routes.inputOptions,
            selection: Binding(
              get: { routes.currentInputID },
              set: { routes.selectInput(id: $0) }))
          InputLevelBar(vm: vm)
          Button("End test", role: .cancel) {
            vm.stopMicTest()
          }
        }
      } else if vm.isTestingSpeaker {
        Section("Speaker test") {
          AudioDevicePicker(
            title: "Output", systemImage: "speaker.wave.2.fill",
            options: routes.outputOptions,
            selection: Binding(
              get: { routes.currentOutputID },
              set: { routes.selectOutput(id: $0) }))
          OutputLevelBar(vm: vm)
          Button("End test", role: .cancel) {
            vm.stopSpeakerTest()
          }
        }
      } else {
        Section {
          Button {
            vm.startMicTest()
          } label: {
            Label("Test microphone", systemImage: "mic.badge.plus")
          }
          .disabled(vm.micPermissionDenied)
          Button {
            vm.startSpeakerTest()
          } label: {
            Label("Test speaker", systemImage: "speaker.wave.2.fill")
          }
          .disabled(vm.micPermissionDenied)
        }
      }
    }
    .sheet(item: $renamingPeer) { peer in
      PairedPeerSheet(connect: connect, peer: peer)
    }
    .pairRequestAlert(connect)
  }
}

struct InCallView: View {
  @Bindable var vm: CallViewModel
  let transport: PeerTransport
  let routes: AudioRouteController

  init(vm: CallViewModel) {
    self.vm = vm
    self.transport = vm.transport
    self.routes = vm.routes
  }

  var body: some View {
    List {
      Section {
        HStack {
          Image(systemName: "waveform")
            .foregroundStyle(.green)
          Text(transport.connectedPeer?.name ?? "Connected")
            .font(.headline)
        }
      }
      Section("Controls") {
        Toggle(isOn: $vm.isMuted) {
          Label("Mute microphone", systemImage: vm.isMuted ? "mic.slash.fill" : "mic.fill")
        }
      }
      Section("Audio input") {
        AudioDevicePicker(
          title: "Microphone", systemImage: "mic",
          options: routes.inputOptions,
          selection: Binding(
            get: { routes.currentInputID },
            set: { routes.selectInput(id: $0) }))
        InputLevelBar(vm: vm)
      }
      Section("Audio output") {
        AudioDevicePicker(
          title: "Output", systemImage: "speaker.wave.2.fill",
          options: routes.outputOptions,
          selection: Binding(
            get: { routes.currentOutputID },
            set: { routes.selectOutput(id: $0) }))
        OutputLevelBar(vm: vm)
      }
      Section {
        Button(role: .destructive) {
          vm.endCall()
        } label: {
          Label("End call", systemImage: "phone.down.fill")
            .frame(maxWidth: .infinity)
        }
      }
    }
    .onAppear {
      routes.refresh()
    }
  }
}

struct InputLevelBar: View {
  let vm: CallViewModel

  var body: some View {
    AudioLevelBar(level: vm.inputLevel)
  }
}

struct OutputLevelBar: View {
  let vm: CallViewModel

  var body: some View {
    AudioLevelBar(level: vm.outputLevel)
  }
}

struct AudioLevelBar: View {
  let level: Float  // 0...1

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(.quaternary)
        Capsule()
          .fill(.green)
          .frame(width: geometry.size.width * CGFloat(min(1, max(0, level))))
      }
    }
    .frame(height: 8)
    .animation(.linear(duration: 0.1), value: level)
  }
}

/// A menu picker over the available devices, or a plain read-only row when
/// there is nothing to choose between.
struct AudioDevicePicker: View {
  let title: String
  let systemImage: String
  let options: [AudioOption]
  @Binding var selection: String?

  var body: some View {
    if options.count > 1 {
      Picker(selection: $selection) {
        ForEach(options) { option in
          Text(option.name).tag(option.id as String?)
        }
      } label: {
        Label(title, systemImage: systemImage)
      }
      .pickerStyle(.menu)
    } else {
      HStack {
        Label(title, systemImage: systemImage)
        Spacer()
        Text(options.first?.name ?? "None")
          .foregroundStyle(.secondary)
      }
    }
  }
}

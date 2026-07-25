#if os(iOS)
import AVKit
#endif
import MultipeerConnectivity
import SwiftUI

public struct ContentView: View {
  @StateObject private var vm = CallViewModel()
  @StateObject private var logs = AppLogStore.shared

  public init() {}

  public var body: some View {
    NavigationStack {
      Group {
        if vm.isInCall {
          InCallView(vm: vm)
        } else {
          LobbyView(vm: vm)
        }
      }
      .navigationTitle(vm.isInCall ? "In Call" : "Local Call")
      .toolbar {
        NavigationLink {
          LogsView(logs: logs)
        } label: {
          Label("Logs", systemImage: "doc.text.magnifyingglass")
        }
      }
    }
    .task {
      await vm.requestMicPermission()
      vm.multipeer.startDiscovery()
    }
    .alert(
      "Incoming call from \(vm.multipeer.pendingInvite?.peer.displayName ?? "")",
      isPresented: Binding(
        get: { vm.multipeer.pendingInvite != nil },
        set: { isPresented in
          if !isPresented, let invite = vm.multipeer.pendingInvite {
            vm.multipeer.respond(invite: invite, accept: false)
          }
        })
    ) {
      Button("Accept") {
        if let invite = vm.multipeer.pendingInvite {
          vm.multipeer.respond(invite: invite, accept: true)
        }
      }
      Button("Decline", role: .cancel) {
        if let invite = vm.multipeer.pendingInvite {
          vm.multipeer.respond(invite: invite, accept: false)
        }
      }
    }
  }
}

struct LogsView: View {
  @ObservedObject var logs: AppLogStore

  var body: some View {
    List {
      if logs.lines.isEmpty {
        Text("No logs yet")
          .foregroundStyle(.secondary)
      }
      ForEach(Array(logs.lines.enumerated()), id: \.offset) { _, line in
        Text(line)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
      }
    }
    .navigationTitle("Logs")
    .toolbar {
      Button("Clear") {
        logs.clear()
      }
    }
  }
}

struct LobbyView: View {
  @ObservedObject var vm: CallViewModel
  @ObservedObject var multipeer: MultipeerManager

  init(vm: CallViewModel) {
    self.vm = vm
    self.multipeer = vm.multipeer
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
      Section("This device") {
        Label(multipeer.peerId.displayName, systemImage: "iphone")
      }
      if let status = multipeer.statusMessage {
        Section {
          Text(status)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      Section("Nearby devices") {
        if multipeer.discoveredPeers.isEmpty {
          HStack {
            ProgressView()
            Text("Searching for nearby devices…")
              .foregroundStyle(.secondary)
          }
        }
        ForEach(multipeer.discoveredPeers, id: \.self) { peer in
          Button {
            multipeer.invite(peer: peer)
          } label: {
            HStack {
              Label(
                peer.displayName,
                systemImage: multipeer.pendingInvite?.peer == peer
                  ? "phone.arrow.down.left" : "phone.arrow.up.right")
              Spacer()
              if multipeer.connectingPeer == peer {
                ProgressView()
              } else if multipeer.pendingInvite?.peer == peer {
                Text("Accept")
                  .foregroundStyle(.green)
              }
            }
          }
          .disabled(multipeer.connectingPeer != nil && multipeer.connectingPeer != peer)
        }
      }
      Section {
        Text("Both devices need this app open, works over bluetooth and peer-to-peer wifi")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }
}

struct InCallView: View {
  @ObservedObject var vm: CallViewModel
  @ObservedObject var multipeer: MultipeerManager
  @ObservedObject var routes: AudioRouteController

  init(vm: CallViewModel) {
    self.vm = vm
    self.multipeer = vm.multipeer
    self.routes = vm.routes
  }

  var body: some View {
    List {
      Section {
        HStack {
          Image(systemName: "waveform")
            .foregroundStyle(.green)
          Text(multipeer.connectedPeer?.displayName ?? "Connected")
            .font(.headline)
        }
      }
      Section("Controls") {
        Toggle(isOn: $vm.isMuted) {
          Label("Mute microphone", systemImage: vm.isMuted ? "mic.slash.fill" : "mic.fill")
        }
      }
      #if os(iOS)
      Section("Audio input") {
        Picker(
          selection: Binding(
            get: { routes.currentInputUid },
            set: { uid in
              let port = routes.availableInputs.first { $0.uid == uid }
              routes.selectInput(port)
            })
        ) {
          ForEach(routes.availableInputs, id: \.uid) { port in
            Text(port.portName).tag(port.uid as String?)
          }
        } label: {
          Label("Microphone", systemImage: "mic")
        }
        .pickerStyle(.inline)
        .labelsHidden()
      }
      Section("Audio output") {
        Toggle(isOn: Binding(get: { routes.isSpeakerOn }, set: { routes.setSpeaker($0) })) {
          Label("Speaker", systemImage: "speaker.wave.2.fill")
        }
        HStack {
          Label("Current output: \(routes.currentOutputName)", systemImage: "airpods")
          Spacer()
          RoutePickerView()
            .frame(width: 44, height: 44)
        }
      }
      #endif
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
      #if os(iOS)
      routes.refresh()
      #endif
    }
  }
}

#if os(iOS)
struct RoutePickerView: UIViewRepresentable {
  func makeUIView(context: Context) -> AVRoutePickerView {
    let view = AVRoutePickerView()
    view.prioritizesVideoDevices = false
    return view
  }

  func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

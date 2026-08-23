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
      // Mic permission and local-network discovery crash XCPreviewAgent
      // (its Info.plist lacks the required usage descriptions)
      guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
        return
      }
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
      Section("Audio input") {
        AudioDevicePicker(
          title: "Microphone", systemImage: "mic",
          options: routes.inputOptions,
          selection: Binding(
            get: { routes.currentInputID },
            set: { routes.selectInput(id: $0) }))
        AudioLevelBar(level: vm.inputLevel)
      }
      Section("Audio output") {
        AudioDevicePicker(
          title: "Output", systemImage: "speaker.wave.2.fill",
          options: routes.outputOptions,
          selection: Binding(
            get: { routes.currentOutputID },
            set: { routes.selectOutput(id: $0) }))
        AudioLevelBar(level: vm.outputLevel)
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

import SwiftUI
import connect

/// The lobby half that needs no button: paired devices are callable whenever
/// they are in range, and the other side rings through CallKit even with the
/// app closed.
struct ConnectSections: View {
  let connect: ConnectManager
  /// Owned by the view that holds the list: a presentation attached to a
  /// section is applied to each of its rows, which then fight to present.
  @Binding var renaming: PairedPeer?

  var body: some View {
    if let status = connect.statusMessage {
      Section {
        Text(status)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    Section("Paired devices") {
      if connect.pairedPeers.isEmpty {
        Text("Pair a device once and you can call it any time both apps are installed and in range")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      ForEach(connect.pairedPeers) { peer in
        PairedPeerRow(connect: connect, peer: peer) {
          renaming = peer
        }
        .swipeActions {
          Button("Unpair", role: .destructive) {
            connect.unpair(peer)
          }
        }
      }
    }
    Section("Pair a nearby device") {
      let unpaired = connect.unpairedNearby()
      if unpaired.isEmpty {
        Text("Open the app on the other device to pair with it")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      ForEach(unpaired) { peer in
        Button {
          connect.pair(with: peer)
        } label: {
          Label(peer.name, systemImage: "link.badge.plus")
        }
      }
    }
  }
}

/// The name and call state are the tap target for renaming; calling is its
/// own button so a mis-tap cannot ring someone.
private struct PairedPeerRow: View {
  let connect: ConnectManager
  let peer: PairedPeer
  let onSelect: () -> Void

  private var callState: ConnectCallState? {
    connect.state.peerId == peer.id ? connect.state : nil
  }

  private var isIdle: Bool {
    connect.state.callId == nil
  }

  var body: some View {
    HStack {
      Button(action: onSelect) {
        VStack(alignment: .leading, spacing: 2) {
          Text(peer.displayName)
            .foregroundStyle(.primary)
          status
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      trailingButton
    }
    .animation(.default, value: connect.state.callId)
  }

  @ViewBuilder private var status: some View {
    switch callState {
    case .outgoing:
      Label("Calling…", systemImage: "phone.arrow.up.right")
        .font(.footnote)
        .foregroundStyle(.secondary)
    case .incoming:
      Label("Ringing", systemImage: "phone.arrow.down.left")
        .font(.footnote)
        .foregroundStyle(.secondary)
    case .active:
      Label("On this call", systemImage: "waveform")
        .font(.footnote)
        .foregroundStyle(.green)
    case .idle, .none:
      Text(connect.isNearby(peer) ? "In range" : "Away")
        .font(.footnote)
        .foregroundStyle(connect.isNearby(peer) ? .green : .secondary)
    }
  }

  @ViewBuilder private var trailingButton: some View {
    if callState != nil {
      Button("End", role: .destructive) {
        connect.endCall()
      }
      .buttonStyle(.bordered)
    } else {
      Button("Call") {
        connect.call(peer)
      }
      .buttonStyle(.bordered)
      .disabled(!connect.isNearby(peer) || !isIdle)
    }
  }
}

/// Renaming, plus the details that are only worth showing when asked for.
struct PairedPeerSheet: View {
  let connect: ConnectManager
  let peer: PairedPeer
  @Environment(\.dismiss) private var dismiss
  @State private var draft: String
  @FocusState private var nameFocused: Bool

  init(connect: ConnectManager, peer: PairedPeer) {
    self.connect = connect
    self.peer = peer
    _draft = State(initialValue: peer.nickname ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(peer.name, text: $draft)
            .focused($nameFocused)
            .submitLabel(.done)
            .onSubmit(save)
        } header: {
          Text("Name")
        } footer: {
          Text("Leave this empty to use \(peer.name), the name the device gives itself")
        }
        Section {
          Button("Unpair", role: .destructive) {
            connect.unpair(peer)
            dismiss()
          }
        } footer: {
          Text("Unpairing stops this device ringing yours. Pair again to undo it.")
        }
      }
      .navigationTitle(peer.displayName)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: save)
        }
      }
      .task { nameFocused = true }
    }
  }

  private func save() {
    connect.rename(peer, to: draft)
    dismiss()
  }
}

extension View {
  func pairRequestAlert(_ connect: ConnectManager) -> some View {
    alert(
      "Pair with \(connect.pendingPairRequest?.name ?? "")",
      isPresented: Binding(
        get: { connect.pendingPairRequest != nil },
        set: { isPresented in
          if !isPresented {
            connect.respondToPairRequest(accept: false)
          }
        })
    ) {
      Button("Pair") {
        connect.respondToPairRequest(accept: true)
      }
      Button("Decline", role: .cancel) {
        connect.respondToPairRequest(accept: false)
      }
    } message: {
      Text("They will be able to call this device while the app is installed and in range")
    }
  }

  func callSilencedAlert(_ connect: ConnectManager) -> some View {
    alert(
      "\(connect.silencedPeerName ?? "That device") has a Focus on",
      isPresented: Binding(
        get: { connect.silencedPeerName != nil },
        set: { isPresented in
          if !isPresented {
            connect.silencedPeerName = nil
          }
        })
    ) {
      Button("OK", role: .cancel) {
        connect.silencedPeerName = nil
      }
    } message: {
      Text(
        "iOS did not ring it. Calling again within three minutes gets through if Allow Repeated Calls is on"
      )
    }
  }
}

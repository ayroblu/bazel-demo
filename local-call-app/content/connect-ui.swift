import SwiftUI
import connect

/// The lobby half that needs no button: paired devices are callable whenever
/// they are in range, and the other side rings through CallKit even with the
/// app closed.
struct ConnectSections: View {
  @ObservedObject var connect: ConnectManager

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
        let inRange = connect.isNearby(peer)
        Button {
          connect.call(peer)
        } label: {
          HStack {
            Label(peer.name, systemImage: "phone.fill")
            Spacer()
            Text(inRange ? "In range" : "Away")
              .font(.footnote)
              .foregroundStyle(inRange ? .green : .secondary)
          }
        }
        .disabled(!inRange)
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

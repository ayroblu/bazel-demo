#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Log
import MultipeerConnectivity

nonisolated let callServiceType = "p2p-audio-call"

nonisolated final class SendableBox<T>: @unchecked Sendable {
  let value: T
  init(_ value: T) {
    self.value = value
  }
}

struct PendingInvite: Identifiable {
  let id = UUID()
  let peer: MCPeerID
  let handler: SendableBox<(Bool, MCSession?) -> Void>
}

private var deviceName: String {
  #if os(macOS)
  Host.current().localizedName ?? ProcessInfo.processInfo.hostName
  #else
  UIDevice.current.name
  #endif
}

class MultipeerManager: ObservableObject {
  let peerId = MCPeerID(displayName: deviceName)
  let session: MCSession
  private let advertiser: MCNearbyServiceAdvertiser
  private let browser: MCNearbyServiceBrowser
  private let delegate = MultipeerDelegate()

  @Published var discoveredPeers: [MCPeerID] = []
  @Published var connectedPeer: MCPeerID?
  @Published var connectingPeer: MCPeerID?
  @Published var pendingInvite: PendingInvite?
  @Published var statusMessage: String?

  init() {
    session = MCSession(peer: peerId, securityIdentity: nil, encryptionPreference: .required)
    advertiser = MCNearbyServiceAdvertiser(
      peer: peerId, discoveryInfo: nil, serviceType: callServiceType)
    browser = MCNearbyServiceBrowser(peer: peerId, serviceType: callServiceType)
    delegate.manager = self
    session.delegate = delegate
    advertiser.delegate = delegate
    browser.delegate = delegate
  }

  var onAudioData: (@Sendable (Data) -> Void)? {
    get { delegate.onAudioData }
    set { delegate.onAudioData = newValue }
  }

  func startDiscovery() {
    log("multipeer start discovery", peerId.displayName, callServiceType)
    advertiser.startAdvertisingPeer()
    browser.startBrowsingForPeers()
    statusMessage = nil
  }

  func invite(peer: MCPeerID) {
    if let invite = pendingInvite {
      guard invite.peer == peer else {
        statusMessage = "Answer the incoming call from \(invite.peer.displayName) first."
        return
      }
      respond(invite: invite, accept: true)
      return
    }
    guard connectingPeer == nil else { return }
    log("multipeer invite", peer.displayName)
    connectingPeer = peer
    statusMessage = "Calling \(peer.displayName)…"
    browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
  }

  func respond(invite: PendingInvite, accept: Bool) {
    log("multipeer respond", invite.peer.displayName, accept)
    pendingInvite = nil
    if accept {
      connectingPeer = invite.peer
      statusMessage = "Connecting to \(invite.peer.displayName)…"
    } else {
      statusMessage = "Declined call from \(invite.peer.displayName)"
    }
    invite.handler.value(accept, session)
  }

  func disconnect(statusMessage message: String? = nil) {
    log("multipeer disconnect")
    session.disconnect()
    connectedPeer = nil
    connectingPeer = nil
    statusMessage = message
  }

  func makeSender() -> @Sendable (Data) -> Void {
    let sessionBox = SendableBox(session)
    return { data in
      let session = sessionBox.value
      let peers = session.connectedPeers
      guard !peers.isEmpty else { return }
      do {
        try session.send(data, toPeers: peers, with: .unreliable)
      } catch {
        log("multipeer send audio failed", error)
      }
    }
  }

  func handleFound(peer: MCPeerID) {
    log("multipeer found peer", peer.displayName)
    if !discoveredPeers.contains(peer) {
      discoveredPeers.append(peer)
    }
  }

  func handleLost(peer: MCPeerID) {
    log("multipeer lost peer", peer.displayName)
    discoveredPeers.removeAll { $0 == peer }
  }

  func handleInvite(from peer: MCPeerID, handler: SendableBox<(Bool, MCSession?) -> Void>) {
    log("multipeer received invite", peer.displayName)
    guard connectedPeer == nil else {
      log("multipeer rejecting invite because already connected", peer.displayName)
      handler.value(false, nil)
      return
    }
    if connectingPeer == peer {
      log("multipeer accepting invite from peer we were already calling", peer.displayName)
      connectingPeer = nil
      statusMessage = "Connecting to \(peer.displayName)…"
      handler.value(true, session)
      return
    }
    guard pendingInvite == nil else {
      log("multipeer rejecting invite because another invite is pending", peer.displayName)
      handler.value(false, nil)
      return
    }
    pendingInvite = PendingInvite(peer: peer, handler: handler)
    statusMessage = "Incoming call from \(peer.displayName)"
  }

  var onCallStarted: (() -> Void)?
  var onCallEnded: (() -> Void)?

  func handleStateChange(peer: MCPeerID, state: MCSessionState) {
    switch state {
    case .connecting:
      connectingPeer = peer
      statusMessage = "Connecting to \(peer.displayName)…"
    case .connected:
      connectingPeer = nil
      connectedPeer = peer
      statusMessage = "Connected to \(peer.displayName)"
      onCallStarted?()
    case .notConnected:
      let wasConnecting = connectingPeer == peer
      let wasConnected = connectedPeer == peer
      if wasConnecting {
        connectingPeer = nil
        statusMessage = "Could not connect to \(peer.displayName). Check permissions and that both apps are open."
      }
      if wasConnected {
        connectedPeer = nil
        statusMessage = "Disconnected from \(peer.displayName)"
        onCallEnded?()
      }
      if !wasConnecting && !wasConnected {
        statusMessage = "Not connected to \(peer.displayName)"
      }
    @unknown default:
      statusMessage = "Unknown connection state for \(peer.displayName)"
    }
  }
}

extension MCSessionState {
  nonisolated var description: String {
    switch self {
    case .notConnected:
      "notConnected"
    case .connecting:
      "connecting"
    case .connected:
      "connected"
    @unknown default:
      "unknown"
    }
  }
}

nonisolated final class MultipeerDelegate: NSObject, MCSessionDelegate,
  MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, @unchecked Sendable
{
  weak var manager: MultipeerManager?
  var onAudioData: (@Sendable (Data) -> Void)?

  func session(_ session: MCSession, peer peerId: MCPeerID, didChange state: MCSessionState) {
    log("multipeer state change", peerId.displayName, state.description, state.rawValue)
    let peer = SendableBox(peerId)
    Task { @MainActor [weak manager] in
      manager?.handleStateChange(peer: peer.value, state: state)
    }
  }

  func session(_ session: MCSession, didReceive data: Data, fromPeer peerId: MCPeerID) {
    onAudioData?(data)
  }

  func session(
    _ session: MCSession, didReceive stream: InputStream, withName streamName: String,
    fromPeer peerId: MCPeerID
  ) {}

  func session(
    _ session: MCSession, didStartReceivingResourceWithName resourceName: String,
    fromPeer peerId: MCPeerID, with progress: Progress
  ) {}

  func session(
    _ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerId: MCPeerID, at localURL: URL?, withError error: Error?
  ) {}

  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerId: MCPeerID,
    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void
  ) {
    let handler = SendableBox(invitationHandler)
    let peer = SendableBox(peerId)
    Task { @MainActor [weak manager] in
      manager?.handleInvite(from: peer.value, handler: handler)
    }
  }

  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error
  ) {
    log("multipeer failed to advertise", error)
  }

  func browser(
    _ browser: MCNearbyServiceBrowser, foundPeer peerId: MCPeerID,
    withDiscoveryInfo info: [String: String]?
  ) {
    let peer = SendableBox(peerId)
    Task { @MainActor [weak manager] in
      manager?.handleFound(peer: peer.value)
    }
  }

  func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerId: MCPeerID) {
    let peer = SendableBox(peerId)
    Task { @MainActor [weak manager] in
      manager?.handleLost(peer: peer.value)
    }
  }

  func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
    log("multipeer failed to browse", error)
  }
}

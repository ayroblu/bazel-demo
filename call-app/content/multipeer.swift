import Log
import MultipeerConnectivity
import UIKit

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

class MultipeerManager: ObservableObject {
  let peerId = MCPeerID(displayName: UIDevice.current.name)
  let session: MCSession
  private let advertiser: MCNearbyServiceAdvertiser
  private let browser: MCNearbyServiceBrowser
  private let delegate = MultipeerDelegate()

  @Published var discoveredPeers: [MCPeerID] = []
  @Published var connectedPeer: MCPeerID?
  @Published var connectingPeer: MCPeerID?
  @Published var pendingInvite: PendingInvite?
  @Published var isDiscovering = false

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
    advertiser.startAdvertisingPeer()
    browser.startBrowsingForPeers()
    isDiscovering = true
  }

  func stopDiscovery() {
    advertiser.stopAdvertisingPeer()
    browser.stopBrowsingForPeers()
    discoveredPeers = []
    isDiscovering = false
  }

  func invite(peer: MCPeerID) {
    connectingPeer = peer
    browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
  }

  func respond(invite: PendingInvite, accept: Bool) {
    if accept {
      connectingPeer = invite.peer
    }
    invite.handler.value(accept, session)
    pendingInvite = nil
  }

  func disconnect() {
    session.disconnect()
    connectedPeer = nil
    connectingPeer = nil
  }

  func makeSender() -> @Sendable (Data) -> Void {
    let sessionBox = SendableBox(session)
    return { data in
      let session = sessionBox.value
      let peers = session.connectedPeers
      guard !peers.isEmpty else { return }
      try? session.send(data, toPeers: peers, with: .unreliable)
    }
  }

  func handleFound(peer: MCPeerID) {
    if !discoveredPeers.contains(peer) {
      discoveredPeers.append(peer)
    }
  }

  func handleLost(peer: MCPeerID) {
    discoveredPeers.removeAll { $0 == peer }
  }

  func handleInvite(from peer: MCPeerID, handler: SendableBox<(Bool, MCSession?) -> Void>) {
    guard pendingInvite == nil, connectedPeer == nil else {
      handler.value(false, nil)
      return
    }
    pendingInvite = PendingInvite(peer: peer, handler: handler)
  }

  var onCallStarted: (() -> Void)?
  var onCallEnded: (() -> Void)?

  func handleStateChange(peer: MCPeerID, state: MCSessionState) {
    switch state {
    case .connecting:
      connectingPeer = peer
    case .connected:
      connectingPeer = nil
      connectedPeer = peer
      onCallStarted?()
    case .notConnected:
      if connectingPeer == peer {
        connectingPeer = nil
      }
      if connectedPeer == peer {
        connectedPeer = nil
        onCallEnded?()
      }
    @unknown default:
      break
    }
  }
}

nonisolated final class MultipeerDelegate: NSObject, MCSessionDelegate,
  MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, @unchecked Sendable
{
  weak var manager: MultipeerManager?
  var onAudioData: (@Sendable (Data) -> Void)?

  func session(_ session: MCSession, peer peerId: MCPeerID, didChange state: MCSessionState) {
    log("multipeer state change", peerId.displayName, state.rawValue)
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

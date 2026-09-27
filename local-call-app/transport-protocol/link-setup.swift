import Foundation

public nonisolated struct LinkCall: Sendable, Equatable {
  public let peerId: UUID
  public let peerIdentity: String
  public let peerName: String
  public let callId: UUID
  public let invites: Bool

  public init(peerId: UUID, peerIdentity: String, peerName: String, callId: UUID, invites: Bool) {
    self.peerId = peerId
    self.peerIdentity = peerIdentity
    self.peerName = peerName
    self.callId = callId
    self.invites = invites
  }
}

/// May hand over several candidates (a dialled peer, connections accepted before their hello); the
/// call protocol keeps the one whose hello matches. `dials` means this side greets first.
public protocol LinkSetup: AnyObject {
  var onCarrier: ((_ carrier: any DatagramCarrier, _ dials: Bool) -> Void)? { get set }
  func begin(_ call: LinkCall)
  func didConnect()
  func dialFailed()
  func cancel()
}

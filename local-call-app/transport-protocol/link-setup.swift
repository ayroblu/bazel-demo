import Foundation

/// The call a link is being set up for, as the bluetooth signalling agreed
/// it. `invites` is true on the side that placed the call.
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

/// How a link technology produces carriers for a call. It may hand over
/// several candidates - a browsed peer being dialled, connections accepted
/// before their hello arrives - and the call protocol keeps the one whose
/// hello matches the call. `dials` is true when this side opened the carrier
/// and should greet first.
public protocol LinkSetup: AnyObject {
  var onCarrier: ((_ carrier: any DatagramCarrier, _ dials: Bool) -> Void)? { get set }
  func begin(_ call: LinkCall)
  /// The call is connected; searching for more candidates can stop.
  func didConnect()
  /// A carrier this side dialled closed before the call came up.
  func dialFailed()
  func cancel()
}

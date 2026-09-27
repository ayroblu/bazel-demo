import Foundation
import awdl
import bluetooth
import l2cap
import transport_protocol

/// Compile-time switch between link technologies, for comparing them on real
/// devices. Both devices must run the same mode.
///
/// - `awdl`: peer-to-peer wifi via Bonjour + DTLS datagrams. Works on any
///   supported iOS, but AWDL's radio duty cycle delivers audio in bursts
///   (~180-330ms gaps measured), which sets the latency floor.
/// - `l2cap`: a bluetooth L2CAP channel on the connection the signalling
///   already holds. ~30ms connection intervals instead of AWDL bursts, but
///   little bandwidth headroom beyond one opus stream.
public nonisolated enum TransportMode: Sendable {
  case awdl
  case l2cap

  func makeLinkSetup(identity: String, link: NearbyLink) -> any LinkSetup {
    switch self {
    case .awdl: AwdlLinkSetup(identity: identity)
    case .l2cap: L2capLinkSetup(link: link)
    }
  }
}

public nonisolated let transportMode: TransportMode = .l2cap

extension PeerTransport {
  public convenience init(identity: String, link: NearbyLink) {
    self.init(identity: identity, setup: transportMode.makeLinkSetup(identity: identity, link: link))
  }
}

import Foundation

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

  public var usesL2cap: Bool { self == .l2cap }
}

public nonisolated let transportMode: TransportMode = .l2cap

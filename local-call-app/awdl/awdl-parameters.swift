import CryptoKit
import Foundation
import Network
import Security

/// Both ends of a call are copies of this app, so the key that encrypts the
/// audio is baked into it. That hides the call from anything else on the
/// link, but it authenticates nobody: any copy of the app holds the same key.
private nonisolated let presharedKeySeed = "local-call-app.peer-audio.v1"
private nonisolated let presharedKeyIdentity = "local-call-app"

public nonisolated let awdlServiceType = "_p2p-audio-call._udp"

/// Peer-to-peer includes AWDL, which is the only path between two devices
/// that share no network.
public nonisolated func awdlParameters() -> NWParameters {
  let parameters = NWParameters(dtls: tlsOptions(), udp: NWProtocolUDP.Options())
  parameters.includePeerToPeer = true
  return parameters
}

private nonisolated func tlsOptions() -> NWProtocolTLS.Options {
  let options = NWProtocolTLS.Options()
  let key = Data(SHA256.hash(data: Data(presharedKeySeed.utf8)))
    .withUnsafeBytes { DispatchData(bytes: $0) }
  let identity = Data(presharedKeyIdentity.utf8)
    .withUnsafeBytes { DispatchData(bytes: $0) }
  sec_protocol_options_add_pre_shared_key(
    options.securityProtocolOptions, key as __DispatchData, identity as __DispatchData)
  // A pre-shared key needs a ciphersuite that can be negotiated without a
  // certificate.
  sec_protocol_options_append_tls_ciphersuite(
    options.securityProtocolOptions, tls_ciphersuite_t.AES_128_GCM_SHA256)
  return options
}

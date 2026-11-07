import NetworkExtension
import address

@objc(PacketTunnelProvider)
final class PacketTunnelProvider: NEPacketTunnelProvider {
  override func startTunnel(options: [String: NSObject]?) async throws {
    let address = (protocolConfiguration as! NETunnelProviderProtocol).serverAddress!
    try await setTunnelNetworkSettings(settings(for: address))
  }

  override func stopTunnel(with reason: NEProviderStopReason) async {}

  override func handleAppMessage(_ messageData: Data) async -> Data? {
    try? await setTunnelNetworkSettings(settings(for: String(decoding: messageData, as: UTF8.self)))
    return nil
  }
}

private func settings(for text: String) -> NEPacketTunnelNetworkSettings {
  let address = ProxyAddress(text)!
  let server = NEProxyServer(address: address.host, port: Int(address.port))
  let proxy = NEProxySettings()
  proxy.httpEnabled = true
  proxy.httpServer = server
  proxy.httpsEnabled = true
  proxy.httpsServer = server
  proxy.excludeSimpleHostnames = true
  proxy.matchDomains = [""]
  let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
  settings.ipv4Settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.255"])
  settings.proxySettings = proxy
  return settings
}

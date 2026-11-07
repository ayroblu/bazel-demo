import Foundation
import NetworkExtension
import Observation
import address

@Observable
final class VPNProxy {
  private(set) var status = NEVPNStatus.invalid
  private(set) var error: String?
  var value = ""
  @ObservationIgnored private var manager: NETunnelProviderManager?

  init() {
    Task { await load() }
    Task {
      for await _ in NotificationCenter.default.notifications(named: .NEVPNStatusDidChange) {
        status = manager?.connection.status ?? .invalid
      }
    }
  }

  var enabled: Bool { [.connecting, .connected, .reasserting].contains(status) }

  func set(_ on: Bool) {
    Task {
      do {
        if on {
          try await start()
        } else {
          manager?.connection.stopVPNTunnel()
        }
        error = nil
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func load() async {
    manager = try? await NETunnelProviderManager.loadAllFromPreferences().first
    value = manager?.protocolConfiguration?.serverAddress ?? value
    status = manager?.connection.status ?? .invalid
  }

  private func start() async throws {
    guard let address = ProxyAddress(value) else {
      throw Failure("Enter host:port, e.g. 192.168.1.20:8888")
    }
    let manager = manager ?? NETunnelProviderManager()
    let configuration = NETunnelProviderProtocol()
    configuration.providerBundleIdentifier = tunnelBundleId
    configuration.serverAddress = address.description
    manager.protocolConfiguration = configuration
    manager.localizedDescription = "NetProx"
    manager.isEnabled = true
    try await manager.saveToPreferences()
    try await manager.loadFromPreferences()
    self.manager = manager
    if enabled, let session = manager.connection as? NETunnelProviderSession {
      try session.sendProviderMessage(Data(address.description.utf8))
    } else {
      try manager.connection.startVPNTunnel()
    }
  }
}

private let tunnelBundleId = "com.ayroblu.net-prox-app.tunnel"

private struct Failure: LocalizedError {
  let errorDescription: String?

  init(_ message: String) {
    errorDescription = message
  }
}

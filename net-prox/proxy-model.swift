import Foundation
import Observation
import proxy

struct Client: Identifiable {
  let id: String
  let count: Int
  let lastSeen: Date
  let userAgent: String?
}

@Observable
final class ProxyModel {
  let port: UInt16 = 8888
  private(set) var snapshot = Snapshot()
  private(set) var addresses: [LocalAddress] = []
  private(set) var names: [String: String] = [:]
  private(set) var upload = 0
  private(set) var download = 0
  private var startError: String?
  @ObservationIgnored private var server: ProxyServer?
  @ObservationIgnored private var lookedUp: Set<String> = []
  @ObservationIgnored private let activity = ProcessInfo.processInfo.beginActivity(
    options: .userInitiatedAllowingIdleSystemSleep, reason: "Proxying requests")

  init() {
    do {
      server = try ProxyServer(port: port)
    } catch {
      startError = "\(error)"
    }
    Task {
      while true {
        refresh()
        try? await Task.sleep(for: .milliseconds(500))
      }
    }
  }

  var error: String? { startError ?? snapshot.failure }

  var active: Int { snapshot.exchanges.count { $0.end == nil } }

  var clients: [Client] {
    Dictionary(grouping: snapshot.exchanges, by: \.client)
      .map { ip, exchanges in
        Client(
          id: ip, count: exchanges.count, lastSeen: exchanges.last!.start,
          userAgent: exchanges.last { $0.userAgent != nil }?.userAgent)
      }
      .sorted { $0.lastSeen > $1.lastSeen }
  }

  func name(of ip: String) -> String {
    names[ip] ?? ip
  }

  private func refresh() {
    let current = localAddresses()
    if current != addresses { addresses = current }
    guard let next = server?.snapshot() else { return }
    upload = (next.sent - snapshot.sent) * 2
    download = (next.received - snapshot.received) * 2
    if next != snapshot { snapshot = next }
    for exchange in next.exchanges where !lookedUp.contains(exchange.client) {
      let ip = exchange.client
      lookedUp.insert(ip)
      Task { names[ip] = await hostName(for: ip) }
    }
  }
}

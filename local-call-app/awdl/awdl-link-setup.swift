import Foundation
import Log
import Network
import transport_protocol

private nonisolated final class Box<T>: @unchecked Sendable {
  let value: T
  init(_ value: T) {
    self.value = value
  }
}

/// The listener stays up through a call so cancelling it cannot disturb the connection it accepted;
/// browsing stops once the call connects.
public final class AwdlLinkSetup: LinkSetup {
  public var onCarrier: ((any DatagramCarrier, Bool) -> Void)?

  private let localIdentity: String
  private var call: LinkCall?
  private var listener: NWListener?
  private var browser: NWBrowser?
  private var discovered: Set<String> = []
  private var hasDialled = false

  public init(identity: String) {
    localIdentity = identity
  }

  public func begin(_ call: LinkCall) {
    log("awdl start discovery", localIdentity, awdlServiceType, "invites", call.invites)
    self.call = call
    hasDialled = false
    startListener()
    startBrowser()
  }

  public func didConnect() {
    stopBrowsing()
  }

  public func dialFailed() {
    hasDialled = false
  }

  public func cancel() {
    guard call != nil || listener != nil || browser != nil else { return }
    log("awdl stop discovery")
    call = nil
    listener?.cancel()
    listener = nil
    stopBrowsing()
  }

  private func stopBrowsing() {
    browser?.cancel()
    browser = nil
    discovered = []
  }

  private func startListener() {
    guard listener == nil else { return }
    do {
      let listener = try NWListener(using: awdlParameters())
      listener.service = NWListener.Service(name: localIdentity, type: awdlServiceType)
      listener.stateUpdateHandler = { state in
        guard case .failed(let error) = state else { return }
        log("awdl failed to advertise", error)
      }
      listener.newConnectionHandler = { [weak self] connection in
        let box = Box(connection)
        Task { @MainActor [weak self] in
          self?.onCarrier?(NWDatagramCarrier(connection: box.value), false)
        }
      }
      listener.start(queue: .main)
      self.listener = listener
    } catch {
      log("awdl failed to listen", error)
    }
  }

  private func startBrowser() {
    guard browser == nil else { return }
    let browser = NWBrowser(
      for: .bonjour(type: awdlServiceType, domain: nil), using: awdlParameters())
    browser.stateUpdateHandler = { state in
      guard case .failed(let error) = state else { return }
      log("awdl failed to browse", error)
    }
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      let box = Box(results.map(\.endpoint))
      Task { @MainActor [weak self] in
        self?.handleBrowseResults(box.value)
      }
    }
    browser.start(queue: .main)
    self.browser = browser
  }

  private func handleBrowseResults(_ endpoints: [NWEndpoint]) {
    var target: NWEndpoint?
    for endpoint in endpoints {
      guard case .service(let identity, _, _, _) = endpoint, identity != localIdentity else {
        continue
      }
      if discovered.insert(identity).inserted {
        log("awdl found peer", identity)
      }
      if identity == call?.peerIdentity {
        target = endpoint
      }
    }
    guard let call, call.invites, !hasDialled, let target else { return }
    hasDialled = true
    log("awdl dial", call.peerName, call.peerIdentity)
    let connection = NWConnection(to: target, using: awdlParameters())
    onCarrier?(NWDatagramCarrier(connection: connection), true)
  }
}

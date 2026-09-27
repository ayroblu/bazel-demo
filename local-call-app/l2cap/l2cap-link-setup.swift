import CoreBluetooth
import Foundation
import Log
import bluetooth
import transport_protocol

/// The channel object must stay referenced or its streams die under the call.
public final class L2capLinkSetup: LinkSetup {
  public var onCarrier: ((any DatagramCarrier, Bool) -> Void)?

  private let link: NearbyLink
  private var call: LinkCall?
  private var channel: CBL2CAPChannel?

  public init(link: NearbyLink) {
    self.link = link
    link.onPublishedPsm = { [weak self] psm in
      self?.handlePublishedPsm(psm)
    }
    link.onCallPsm = { [weak self] callId, psm in
      self?.handleCallPsm(callId: callId, psm: psm)
    }
    link.onCallChannel = { [weak self] channel in
      self?.handleChannel(channel)
    }
  }

  public func begin(_ call: LinkCall) {
    log("l2cap setup, inviter", call.invites)
    self.call = call
    guard !call.invites else { return }
    link.publishCallChannel()
  }

  public func didConnect() {}

  public func dialFailed() {}

  public func cancel() {
    call = nil
    channel = nil
    link.unpublishCallChannel()
  }

  private func handlePublishedPsm(_ psm: CBL2CAPPSM) {
    guard let call, !call.invites else { return }
    link.send(.transportPsm(callId: call.callId, psm: UInt16(psm)), to: call.peerId)
  }

  private func handleCallPsm(callId: UUID, psm: CBL2CAPPSM) {
    guard let call, call.invites, call.callId == callId, channel == nil else { return }
    link.openCallChannel(peerId: call.peerId, psm: psm)
  }

  private func handleChannel(_ channel: CBL2CAPChannel) {
    guard let call, let input = channel.inputStream, let output = channel.outputStream,
      let secret = link.secret(for: call.peerId)
    else {
      log("l2cap channel unusable")
      return
    }
    self.channel = channel
    let carrier = StreamDatagramCarrier(
      input: input, output: output, secret: secret, label: "l2cap")
    onCarrier?(carrier, call.invites)
  }
}

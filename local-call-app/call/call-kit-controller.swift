import AVFoundation
import CallKit
import Foundation
import Log

/// Wraps CallKit so the rest of the module talks in call ids and intents. The
/// system owns the audio session for these calls: the engine may only start
/// once `onAudioActivated` fires.
class CallKitController {
  private let provider: CXProvider
  private let controller = CXCallController()
  private let delegate = CallKitDelegate()

  var onStartOutgoing: ((UUID) -> Void)?
  var onStartFailed: ((UUID) -> Void)?
  var onAnswer: ((UUID) -> Void)?
  var onEnd: ((UUID) -> Void)?
  var onMute: ((Bool) -> Void)?
  var onAudioActivated: (() -> Void)?
  var onAudioDeactivated: (() -> Void)?

  init() {
    let configuration = CXProviderConfiguration()
    configuration.supportsVideo = false
    configuration.maximumCallGroups = 1
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.generic]
    provider = CXProvider(configuration: configuration)
    delegate.controller = self
    provider.setDelegate(delegate, queue: nil)
  }

  enum IncomingResult {
    case reported
    /// A Focus filtered the call, so nothing rang and nothing was shown.
    case silenced
    case failed
  }

  func reportIncoming(callId: UUID, name: String) async -> IncomingResult {
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: name)
    update.localizedCallerName = name
    update.hasVideo = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsHolding = false
    do {
      try await provider.reportNewIncomingCall(with: callId, update: update)
      log("callkit reported incoming", callId.uuidString, name)
      return .reported
    } catch {
      log("callkit failed to report incoming", error)
      let filtered = (error as? CXErrorCodeIncomingCallError)?.code == .filteredByDoNotDisturb
      return filtered ? .silenced : .failed
    }
  }

  func startOutgoing(callId: UUID, name: String) {
    let handle = CXHandle(type: .generic, value: name)
    let action = CXStartCallAction(call: callId, handle: handle)
    action.isVideo = false
    action.contactIdentifier = name
    request(action) { [weak self] in
      self?.onStartFailed?(callId)
    }
  }

  func reportOutgoingConnecting(callId: UUID) {
    provider.reportOutgoingCall(with: callId, startedConnectingAt: nil)
  }

  func reportOutgoingConnected(callId: UUID) {
    provider.reportOutgoingCall(with: callId, connectedAt: nil)
  }

  /// Ends a call the user did not end themselves, e.g. the other side hung up
  /// or the audio transport never came up.
  func reportEnded(callId: UUID, reason: CXCallEndedReason) {
    log("callkit report ended", callId.uuidString, reason.rawValue)
    provider.reportCall(with: callId, endedAt: nil, reason: reason)
  }

  /// Ends a call from our own UI, which has to go through a transaction so
  /// the system call log and UI agree with us.
  func requestEnd(callId: UUID) {
    request(CXEndCallAction(call: callId))
  }

  func requestMute(callId: UUID, muted: Bool) {
    request(CXSetMutedCallAction(call: callId, muted: muted))
  }

  private func request(_ action: CXAction, onFailure: (@MainActor () -> Void)? = nil) {
    let name = String(describing: type(of: action))
    controller.request(CXTransaction(action: action)) { error in
      guard let error else { return }
      log("callkit transaction failed", name, error)
      guard let onFailure else { return }
      Task { @MainActor in onFailure() }
    }
  }
}

nonisolated final class CallKitDelegate: NSObject, CXProviderDelegate, @unchecked Sendable {
  weak var controller: CallKitController?

  private func onMain(_ body: @escaping @MainActor (CallKitController) -> Void) {
    Task { @MainActor [weak controller] in
      guard let controller else { return }
      body(controller)
    }
  }

  func providerDidReset(_ provider: CXProvider) {
    log("callkit provider reset")
    onMain { $0.onAudioDeactivated?() }
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    let callId = action.callUUID
    action.fulfill()
    onMain {
      $0.reportOutgoingConnecting(callId: callId)
      $0.onStartOutgoing?(callId)
    }
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    let callId = action.callUUID
    action.fulfill()
    onMain { $0.onAnswer?(callId) }
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    let callId = action.callUUID
    action.fulfill()
    onMain { $0.onEnd?(callId) }
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    let muted = action.isMuted
    action.fulfill()
    onMain { $0.onMute?(muted) }
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    log("callkit audio session activated")
    onMain { $0.onAudioActivated?() }
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    log("callkit audio session deactivated")
    onMain { $0.onAudioDeactivated?() }
  }
}

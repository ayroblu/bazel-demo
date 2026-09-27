import Foundation
import Observation

public struct AudioOption: Identifiable, Hashable {
  public let id: String
  public let name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

public nonisolated let isRunningInPreview =
  ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

import AVFoundation
import Log
import UIKit

@Observable public class AudioRouteController {
  private let session = AVAudioSession.sharedInstance()

  public static let automaticOutputID = "automatic"
  public static let speakerOutputID = "speaker"

  public var inputOptions: [AudioOption] = []
  public var outputOptions: [AudioOption] = []
  public var currentInputID: String?
  public var currentOutputID: String? = automaticOutputID
  private var pinnedInputUid: String?
  private var automaticOutputName: String?
  private var automaticIsSpeaker = true
  private var followsProximity = false
  private var isOnSpeaker = false
  private var isNearEar = false

  public var onInterruption: ((Bool) -> Void)?

  public init() {
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.refresh()
      }
    }
    // A .playAndRecord session does not mix, so any app that starts playing
    // audio takes the session, stops our engine and leaves it stopped. The
    // call is silent both ways until we ask for the session back.
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { [weak self] note in
      guard
        let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
        let type = AVAudioSession.InterruptionType(rawValue: raw)
      else { return }
      let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(
        AVAudioSession.InterruptionOptions.init(rawValue:))
      log(
        "audio session interruption", type == .began ? "began" : "ended", "shouldResume",
        options?.contains(.shouldResume) ?? false)
      Task { @MainActor in
        self?.onInterruption?(type == .began)
      }
    }
    NotificationCenter.default.addObserver(
      forName: UIDevice.proximityStateDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.applyProximityRoute()
      }
    }
  }

  /// .defaultToSpeaker only applies when the receiver would otherwise be
  /// chosen; connected AirPods or headphones still win, and we no longer
  /// force an override to the speaker on call start.
  func configure(defaultToSpeaker: Bool = true) throws {
    var options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP]
    if defaultToSpeaker {
      options.insert(.defaultToSpeaker)
    }
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
    // The default ~23ms IO buffer is capture-to-render latency on both ends;
    // 10ms is the shortest that stays reliable on Bluetooth routes.
    try? session.setPreferredIOBufferDuration(0.01)
  }

  public func activate(proximityRouting: Bool = true) throws {
    try configure()
    try session.setActive(true)
    followsProximity = proximityRouting
    refresh()
  }

  public func adopt() throws {
    try configure()
    followsProximity = true
    refresh()
  }

  public func deactivate() {
    stopProximityRouting()
    try? session.setActive(false, options: .notifyOthersOnDeactivation)
    currentOutputID = Self.automaticOutputID
  }

  public func stopProximityRouting() {
    followsProximity = false
    if isNearEar {
      isNearEar = false
      try? configure()
    }
    updateProximityMonitoring()
  }

  private func updateProximityMonitoring() {
    let device = UIDevice.current
    let wanted = followsProximity && (isOnSpeaker || isNearEar)
    guard wanted != device.isProximityMonitoringEnabled else { return }
    device.isProximityMonitoringEnabled = wanted
    log("proximity monitoring", device.isProximityMonitoringEnabled)
  }

  /// `.defaultToSpeaker` outranks a `.none` port override and only a category
  /// change clears it, so reaching the receiver means reconfiguring.
  private func applyProximityRoute() {
    let nearEar = UIDevice.current.proximityState
    guard followsProximity, nearEar != isNearEar else { return }
    isNearEar = nearEar
    do {
      if nearEar {
        try configure(defaultToSpeaker: false)
        try session.overrideOutputAudioPort(.none)
      } else {
        try configure()
        if currentOutputID == Self.speakerOutputID {
          try session.overrideOutputAudioPort(.speaker)
        }
      }
      log("proximity route", nearEar ? "receiver" : "speaker")
    } catch {
      log("failed to follow proximity", error)
      isNearEar = false
    }
  }

  public func refresh() {
    guard !isRunningInPreview else { return }
    let inputs = session.availableInputs ?? []
    inputOptions = inputs.map { AudioOption(id: $0.uid, name: $0.portName) }
    currentInputID = pinnedInputUid ?? session.currentRoute.inputs.first?.uid
    // The system silently clears a speaker override when the route changes
    // (e.g. AirPods connect); snap the published choice back to reality.
    let onSpeaker = session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
    let outputNames = session.currentRoute.outputs.map { $0.portName }.joined(separator: ", ")
    if !isNearEar {
      if currentOutputID == Self.speakerOutputID && !onSpeaker {
        currentOutputID = Self.automaticOutputID
      }
      if currentOutputID == Self.automaticOutputID, !outputNames.isEmpty {
        automaticOutputName = outputNames
        automaticIsSpeaker = onSpeaker
      }
      if automaticIsSpeaker {
        outputOptions = [
          AudioOption(id: Self.automaticOutputID, name: automaticOutputName ?? "Speaker")
        ]
      } else {
        outputOptions = [
          AudioOption(id: Self.automaticOutputID, name: automaticOutputName ?? "Default"),
          AudioOption(id: Self.speakerOutputID, name: "Speaker"),
        ]
      }
      isOnSpeaker = onSpeaker
    }
    updateProximityMonitoring()
    if let pinned = pinnedInputUid, !inputs.contains(where: { $0.uid == pinned }) {
      log("pinned input disappeared, following default")
      pinnedInputUid = nil
      try? session.setPreferredInput(nil)
    }
    log(
      "audio route", "inputs", session.currentRoute.inputs.map { $0.portName }.joined(separator: ","),
      "outputs", outputNames, "pinned input", pinnedInputUid ?? "none",
      "output", currentOutputID ?? "none")
  }

  public func selectInput(id: String?) {
    log("select input tapped", id ?? "none", "current", currentInputID ?? "none")
    if isRunningInPreview {
      currentInputID = id
      return
    }
    guard let port = session.availableInputs?.first(where: { $0.uid == id }) else {
      log(
        "select input has no matching port", id ?? "none", "available",
        (session.availableInputs ?? []).map { $0.uid }.joined(separator: ","))
      return
    }
    do {
      // Always request the tapped port directly. Clearing the preference first
      // creates an intermediate route and makes a tap on the current/default
      // item look like a no-op to SwiftUI and AVAudioSession.
      try session.setPreferredInput(port)
      pinnedInputUid = port.uid
      currentInputID = port.uid
      log("selected input", port.portName)
    } catch {
      log("failed to set preferred input", error)
      refresh()
    }
  }

  public func selectOutput(id: String?) {
    log("select output tapped", id ?? "none", "current", currentOutputID ?? "none")
    guard let id else { return }
    if isRunningInPreview {
      currentOutputID = id
      return
    }
    do {
      try session.overrideOutputAudioPort(id == Self.speakerOutputID ? .speaker : .none)
      currentOutputID = id
      log("selected output", id)
    } catch {
      log("failed to override output", error)
    }
    refresh()
  }
}

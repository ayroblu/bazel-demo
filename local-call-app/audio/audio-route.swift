import Foundation
import Observation

/// A platform-neutral device choice rendered by the in-call pickers.
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

/// Follows the system default route until the user selects a specific input.
/// Each picker action pins that exact port so repeated switching is explicit
/// and does not pass through an intermediate automatic route.
@Observable public class AudioRouteController {
  private let session = AVAudioSession.sharedInstance()

  public static let automaticOutputID = "automatic"
  public static let speakerOutputID = "speaker"

  public var inputOptions: [AudioOption] = []
  public var outputOptions: [AudioOption] = []
  public var currentInputID: String?
  public var currentOutputID: String? = automaticOutputID
  // nil = follow the system default input.
  private var pinnedInputUid: String?
  // Where automatic routing last pointed while no speaker override was
  // active, so the option keeps its device name (e.g. "AirPods Pro") while
  // the override temporarily routes to the speaker.
  private var automaticOutputName: String?
  private var automaticIsSpeaker = true
  private var followsProximity = false
  private var isOnSpeaker = false
  private var isNearEar = false

  /// Called with true when another app takes the audio session, false when it
  /// hands it back.
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
  }

  /// A mic test has no reason to blank the screen or move to the receiver,
  /// so only calls follow proximity.
  public func activate(proximityRouting: Bool = true) throws {
    try configure()
    try session.setActive(true)
    followsProximity = proximityRouting
    refresh()
  }

  /// CallKit owns the session for a CallKit call: it activates it for us and
  /// deactivates it when the call ends, so we only configure and read it.
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

  /// CallKit deactivates its own session, so ending such a call has to stop
  /// the sensor through here rather than through `deactivate()`.
  public func stopProximityRouting() {
    followsProximity = false
    if isNearEar {
      isNearEar = false
      try? configure()
    }
    updateProximityMonitoring()
  }

  /// The sensor also blanks the screen, so it runs only while the call's
  /// audio is on the built-in speaker, and stays on while near the ear so the
  /// move back away is still reported.
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
    // The receiver is a temporary proximity route rather than a choice, so
    // the published output stays on the one to come back to.
    if !isNearEar {
      if currentOutputID == Self.speakerOutputID && !onSpeaker {
        currentOutputID = Self.automaticOutputID
      }
      // The automatic option is named after the device it routes to, e.g.
      // "AirPods Pro". When automatic routing already goes to the built-in
      // speaker the override option would be a duplicate, so offer only one.
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
    // A pinned input that disappeared falls back to following the default.
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

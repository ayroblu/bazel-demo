import Foundation

/// A platform-neutral device choice rendered by the in-call pickers.
struct AudioOption: Identifiable, Hashable {
  let id: String
  let name: String
}

nonisolated let isRunningInPreview =
  ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

#if os(iOS)
import AVFoundation
import Log

/// Follows the system default route unless the user pins a specific input.
/// Picking the input the system would use anyway clears the pin, so the call
/// keeps following future route changes (e.g. AirPods connecting) again.
class AudioRouteController: ObservableObject {
  private let session = AVAudioSession.sharedInstance()

  static let automaticOutputID = "automatic"
  static let speakerOutputID = "speaker"

  @Published var inputOptions: [AudioOption] = []
  @Published var outputOptions: [AudioOption] = []
  @Published var currentInputID: String?
  @Published var currentOutputID: String? = automaticOutputID
  // nil = follow the system default input.
  private var pinnedInputUid: String?
  // Where automatic routing last pointed while no speaker override was
  // active, so the option keeps its device name (e.g. "AirPods Pro") while
  // the override temporarily routes to the speaker.
  private var automaticOutputName: String?
  private var automaticIsSpeaker = true

  init() {
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.refresh()
      }
    }
  }

  func activate() throws {
    // .defaultToSpeaker only applies when the receiver would otherwise be
    // chosen; connected AirPods or headphones still win, and we no longer
    // force an override to the speaker on call start.
    try session.setCategory(
      .playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
    try session.setActive(true)
    refresh()
  }

  func deactivate() {
    try? session.setActive(false, options: .notifyOthersOnDeactivation)
    currentOutputID = Self.automaticOutputID
  }

  func refresh() {
    guard !isRunningInPreview else { return }
    let inputs = session.availableInputs ?? []
    inputOptions = inputs.map { AudioOption(id: $0.uid, name: $0.portName) }
    currentInputID = session.currentRoute.inputs.first?.uid
    // The system silently clears a speaker override when the route changes
    // (e.g. AirPods connect); snap the published choice back to reality.
    let onSpeaker = session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
    if currentOutputID == Self.speakerOutputID && !onSpeaker {
      currentOutputID = Self.automaticOutputID
    }
    // The automatic option is named after the device it routes to, e.g.
    // "AirPods Pro". When automatic routing already goes to the built-in
    // speaker the override option would be a duplicate, so offer only one.
    let outputNames = session.currentRoute.outputs.map { $0.portName }.joined(separator: ", ")
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

  func selectInput(id: String?) {
    if isRunningInPreview {
      currentInputID = id
      return
    }
    guard let port = session.availableInputs?.first(where: { $0.uid == id }) else { return }
    do {
      // Clear the preference first to learn what the default route would
      // be. If the user picked exactly that, stay unpinned so the route
      // keeps following the system default.
      try session.setPreferredInput(nil)
      if session.currentRoute.inputs.first?.uid == port.uid {
        pinnedInputUid = nil
        log("selected default input, following default", port.portName)
      } else {
        try session.setPreferredInput(port)
        pinnedInputUid = port.uid
        log("pinned input", port.portName)
      }
    } catch {
      log("failed to set preferred input", error)
    }
    refresh()
  }

  func selectOutput(id: String?) {
    guard let id else { return }
    if isRunningInPreview {
      currentOutputID = id
      return
    }
    do {
      try session.overrideOutputAudioPort(id == Self.speakerOutputID ? .speaker : .none)
      currentOutputID = id
    } catch {
      log("failed to override output", error)
    }
    refresh()
  }
}
#endif

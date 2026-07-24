#if os(iOS)
import AVFoundation
import Log

typealias AudioInputDevice = AVAudioSessionPortDescription

class AudioRouteController: ObservableObject {
  private let session = AVAudioSession.sharedInstance()

  @Published var availableInputs: [AudioInputDevice] = []
  @Published var currentInputUid: String?
  @Published var currentOutputName: String = ""
  @Published var isSpeakerOn = false

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
    try session.setCategory(
      .playAndRecord, mode: .default,
      options: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker])
    try session.setActive(true)
    try? session.overrideOutputAudioPort(.speaker)
    isSpeakerOn = true
    refresh()
  }

  func deactivate() {
    try? session.setActive(false, options: .notifyOthersOnDeactivation)
    isSpeakerOn = false
  }

  func refresh() {
    availableInputs = session.availableInputs ?? []
    currentInputUid = session.currentRoute.inputs.first?.uid
    currentOutputName = session.currentRoute.outputs.map { $0.portName }.joined(separator: ", ")
    log(
      "audio route", "inputs", session.currentRoute.inputs.map { $0.portName }.joined(separator: ","),
      "outputs", currentOutputName, "speaker", isSpeakerOn)
  }

  func selectInput(_ port: AVAudioSessionPortDescription?) {
    do {
      try session.setPreferredInput(port)
    } catch {
      log("failed to set preferred input", error)
    }
    refresh()
  }

  func setSpeaker(_ enabled: Bool) {
    do {
      try session.overrideOutputAudioPort(enabled ? .speaker : .none)
      isSpeakerOn = enabled
    } catch {
      log("failed to override output", error)
    }
    refresh()
  }
}
#endif

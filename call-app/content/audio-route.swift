import AVFoundation
import Log

class AudioRouteController: ObservableObject {
  private let session = AVAudioSession.sharedInstance()

  @Published var availableInputs: [AVAudioSessionPortDescription] = []
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
      .playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
    try session.setActive(true)
    isSpeakerOn = false
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

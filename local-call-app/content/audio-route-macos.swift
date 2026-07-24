#if os(macOS)
import AVFoundation
import Log

typealias AudioInputDevice = String

class AudioRouteController: ObservableObject {
  @Published var availableInputs: [AudioInputDevice] = []
  @Published var currentInputUid: String?
  @Published var currentOutputName: String = "System Default"
  @Published var isSpeakerOn = false

  func activate() throws {
    refresh()
  }

  func deactivate() {
    isSpeakerOn = false
  }

  func refresh() {
    currentOutputName = "System Default"
  }

  func selectInput(_ input: String?) {
    currentInputUid = input
  }

  func setSpeaker(_ enabled: Bool) {
    isSpeakerOn = enabled
  }
}
#endif

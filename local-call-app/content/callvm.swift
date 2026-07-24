import AVFoundation
import Log
import MultipeerConnectivity

class CallViewModel: ObservableObject {
  let multipeer = MultipeerManager()
  let routes = AudioRouteController()
  private let audio = CallAudioEngine()

  @Published var isInCall = false
  @Published var micPermissionDenied = false
  @Published var isMuted = false {
    didSet {
      audio.isMuted = isMuted
    }
  }

  init() {
    audio.onOutgoingAudio = multipeer.makeSender()
    let audioBox = SendableBox(audio)
    multipeer.onAudioData = { data in
      audioBox.value.playIncoming(data)
    }
    multipeer.onCallStarted = { [weak self] in
      self?.startAudio()
    }
    multipeer.onCallEnded = { [weak self] in
      self?.stopAudio()
    }
  }

  func requestMicPermission() async {
    let granted = await RecordingPermission.hasPermissionToRecord()
    micPermissionDenied = !granted
    log("call mic permission", granted)
  }

  private func startAudio() {
    log("call audio starting")
    do {
      try routes.activate()
      log("call audio route activated")
      try audio.start()
      log("call audio started")
      isMuted = false
      isInCall = true
    } catch {
      log("failed to start audio", error)
      audio.stop()
      routes.deactivate()
      isInCall = false
      multipeer.disconnect(statusMessage: "Connected, but audio failed to start: \(error.localizedDescription)")
    }
  }

  private func stopAudio() {
    audio.stop()
    routes.deactivate()
    isInCall = false
  }

  func endCall() {
    multipeer.disconnect()
    stopAudio()
  }
}

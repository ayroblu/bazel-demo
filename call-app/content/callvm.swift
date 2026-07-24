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
    let granted = await AVAudioApplication.hasPermissionToRecord()
    micPermissionDenied = !granted
  }

  private func startAudio() {
    do {
      try routes.activate()
      try audio.start()
      isMuted = false
      isInCall = true
    } catch {
      log("failed to start audio", error)
      endCall()
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

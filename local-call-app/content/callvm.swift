import AVFoundation
import Log
import MultipeerConnectivity

class CallViewModel: ObservableObject {
  let multipeer = MultipeerManager()
  let routes = AudioRouteController()
  private let audio = CallAudioEngine()

  @Published var isInCall = false
  @Published var micPermissionDenied = false
  @Published var inputLevel: Float = 0
  @Published var outputLevel: Float = 0
  private var levelTask: Task<Void, Never>?
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
    #if os(macOS)
    routes.onDevicesChanged = { [weak self] input, output in
      self?.audio.setPreferredDevices(input: input, output: output)
    }
    #endif
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
      startLevelPolling()
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
    levelTask?.cancel()
    levelTask = nil
    inputLevel = 0
    outputLevel = 0
  }

  /// The engine accumulates peak levels off the audio threads; poll them at
  /// 10Hz with a fast attack and slow release so the meters read smoothly.
  private func startLevelPolling() {
    levelTask?.cancel()
    levelTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(100))
        guard let self else { return }
        let levels = self.audio.takeLevels()
        // sqrt maps linear peaks onto a more perceptual bar scale
        self.inputLevel = max(min(1, levels.input.squareRoot()), self.inputLevel * 0.7)
        self.outputLevel = max(min(1, levels.output.squareRoot()), self.outputLevel * 0.7)
      }
    }
  }

  func endCall() {
    multipeer.disconnect()
    stopAudio()
  }
}

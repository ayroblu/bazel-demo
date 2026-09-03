import AVFoundation
import Log
import MultipeerConnectivity

class CallViewModel: ObservableObject {
  let multipeer = MultipeerManager()
  let routes = AudioRouteController()
  private let audio = CallAudioEngine()

  @Published var isInCall = false
  @Published var isTestingMic = false
  @Published var micPermissionDenied = false
  @Published var inputLevel: Float = 0
  @Published var outputLevel: Float = 0
  private var levelTask: Task<Void, Never>?
  private var statsTask: Task<Void, Never>?
  private var isPlayingDisconnectChime = false
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

  /// Runs the capture side of the audio engine locally so the user can
  /// check their mic and input picker without being in a call. Nothing is
  /// sent: the outgoing sender no-ops with no connected peers.
  func startMicTest() {
    guard !isInCall, !isTestingMic else { return }
    log("mic test starting")
    do {
      try routes.activate()
      try audio.start()
      isMuted = false
      isTestingMic = true
      startLevelPolling()
    } catch {
      log("failed to start mic test", error)
      audio.stop()
      routes.deactivate()
    }
  }

  func stopMicTest() {
    guard isTestingMic else { return }
    log("mic test stopped")
    isTestingMic = false
    audio.stop()
    routes.deactivate()
    stopLevelPolling()
  }

  private func startAudio() {
    log("call audio starting")
    // An incoming call can connect mid-test; hand the engine over cleanly.
    stopMicTest()
    do {
      try routes.activate()
      log("call audio route activated")
      try audio.start()
      log("call audio started")
      isMuted = false
      isInCall = true
      startLevelPolling()
      startStatsLogging()
    } catch {
      log("failed to start audio", error)
      audio.stop()
      routes.deactivate()
      isInCall = false
      multipeer.disconnect(statusMessage: "Connected, but audio failed to start: \(error.localizedDescription)")
    }
  }

  /// The chime plays through the call's engine and route, so the engine is
  /// only torn down once it has finished. The timeout covers a chime that
  /// never reports back, e.g. when the route dies with the call.
  private func stopAudio() {
    log("call audio stopping", multipeer.callStateSummary(), playbackSummary())
    isInCall = false
    stopLevelPolling()
    statsTask?.cancel()
    statsTask = nil
    guard !isPlayingDisconnectChime else { return }
    isPlayingDisconnectChime = true
    audio.playChime {
      Task { @MainActor [weak self] in
        self?.finishStopAudio()
      }
    }
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(1200))
      self?.finishStopAudio()
    }
  }

  private func finishStopAudio() {
    guard isPlayingDisconnectChime else { return }
    isPlayingDisconnectChime = false
    // A mic test or a new call started while the chime was playing owns the
    // engine now.
    guard !isInCall, !isTestingMic else { return }
    audio.stop()
    routes.deactivate()
  }

  private func playbackSummary() -> String {
    let stats = audio.playbackStats()
    return
      "playback backlog=\(stats.backlogMs)ms played=\(stats.playedMs)ms dropped=\(stats.droppedMs)ms"
  }

  /// A heartbeat while in a call: without it a drop leaves no trace of which
  /// side stopped sending, or whether audio was still flowing beforehand.
  private func startStatsLogging() {
    statsTask?.cancel()
    statsTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard let self, self.isInCall else { return }
        log("call stats", self.multipeer.callStateSummary(), self.playbackSummary())
      }
    }
  }

  private func stopLevelPolling() {
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

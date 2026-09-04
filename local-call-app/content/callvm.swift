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
    routes.onInterruption = { [weak self] began in
      self?.handleInterruption(began: began)
    }
    #if os(macOS)
    routes.onDevicesChanged = { [weak self] input, output in
      self?.audio.setPreferredDevices(input: input, output: output)
    }
    #endif
  }

  /// The system stops the engine and deactivates the session when another app
  /// takes it, and never gives it back on its own. Stopping cleanly also ends
  /// the engine's own restart attempts, which cannot succeed while the session
  /// belongs to somebody else.
  private func handleInterruption(began: Bool) {
    guard isInCall || isTestingMic else { return }
    if began {
      // The session is already gone by the time this arrives, so stopping is
      // bookkeeping, not a choice. A call should not lose to another app's
      // audio though, so ask for the session straight back, which stops
      // whatever took it. A mic test is not worth fighting for.
      log("call audio interrupted, stopping engine")
      audio.stop()
      guard isInCall else { return }
      resumeAudio(attempt: 1)
      return
    }
    resumeAudio(attempt: 1)
  }

  private func resumeAudio(attempt: Int) {
    guard isInCall || isTestingMic, !audio.isActive else { return }
    do {
      try routes.activate()
      try audio.start()
      log("call audio resumed", "attempt", attempt)
    } catch {
      log("call audio resume failed", "attempt", attempt, error)
      // The other app can hold the session briefly after handing it back.
      guard attempt < 5 else { return }
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .milliseconds(500))
        self?.resumeAudio(attempt: attempt + 1)
      }
    }
  }

  /// The interruption ended notification does not always arrive, so returning
  /// to the app is a second chance to notice the audio is dead.
  func resumeAudioIfStopped() {
    guard isInCall || isTestingMic, !audio.isActive else { return }
    log("call audio stopped on foreground, resuming")
    resumeAudio(attempt: 1)
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
    return String(
      format: "playback backlog=%dms received=%dms skipped=%dms resyncs=%d arrivalRate=%.2f",
      stats.backlogMs, stats.receivedMs, stats.skippedMs, stats.resyncs, stats.arrivalRate)
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

import Foundation
import Log
import Observation
import audio
import call
import transport
import transport_protocol

@Observable class CallViewModel {
  static let shared = CallViewModel()

  let transport = PeerTransport(
    identity: ConnectManager.shared.localId.uuidString, link: ConnectManager.shared.link)
  let routes = AudioRouteController()
  private let audio = CallAudioEngine()

  var isInCall = false
  var isTestingMic = false
  var isTestingSpeaker = false
  private var isTesting: Bool { isTestingMic || isTestingSpeaker }
  private var speakerToneTask: Task<Void, Never>?
  var micPermissionDenied = false
  var inputLevel: Float = 0
  var outputLevel: Float = 0
  var networkRttMs: Int?
  var endToEndMs: Int?
  var downKbps: Int?
  var upKbps: Int?
  private var lastBytesSample: (at: Date, sent: Int, received: Int)?
  private var levelTask: Task<Void, Never>?
  private var statsTask: Task<Void, Never>?
  private var isPlayingDisconnectChime = false
  let connect = ConnectManager.shared
  private var isSystemCall = false
  private var isSystemAudioActive = false
  private var isApplyingSystemMute = false
  var isMuted = false {
    didSet {
      audio.isMuted = isMuted
      guard isSystemCall, !isApplyingSystemMute else { return }
      connect.setMuted(isMuted)
    }
  }

  init() {
    audio.onOutgoingAudio = transport.makeSender()
    let audioBox = SendableBox(audio)
    transport.setCaptureDelayProvider {
      audioBox.value.captureDelayMs()
    }
    transport.onAudioData = { seq, data in
      audioBox.value.playIncoming(seq: seq, data: data)
    }
    transport.onCallStarted = { [weak self] in
      self?.handleTransportConnected()
    }
    transport.onCallEnded = { [weak self] in
      self?.handleTransportEnded()
    }
    routes.onInterruption = { [weak self] began in
      self?.handleInterruption(began: began)
    }
    connect.onStartTransport = { [weak self] peerId, callId, peerName, invites in
      guard let self else { return }
      self.isSystemCall = true
      try? self.routes.adopt()
      self.transport.beginAutoConnect(
        LinkCall(
          peerId: peerId, peerIdentity: peerId.uuidString, peerName: peerName, callId: callId,
          invites: invites))
    }
    connect.onStopTransport = { [weak self] in
      guard let self else { return }
      self.transport.disconnect()
      self.transport.cancelAutoConnect()
      self.isSystemCall = false
      self.isSystemAudioActive = false
      self.stopAudio()
    }
    connect.onAudioActivated = { [weak self] in
      self?.startSystemAudio()
    }
    connect.onAudioDeactivated = { [weak self] in
      self?.isSystemAudioActive = false
    }
    connect.onMute = { [weak self] muted in
      guard let self else { return }
      self.isApplyingSystemMute = true
      self.isMuted = muted
      self.isApplyingSystemMute = false
    }
  }

  func startConnectServices() {
    log("transport mode", String(describing: transportMode))
    connect.start()
  }

  func setConnectScanning(_ scanning: Bool) {
    connect.setScanning(scanning)
  }

  private func handleTransportConnected() {
    if isSystemCall {
      connect.transportDidConnect()
      if isSystemAudioActive, !audio.isActive {
        startAudio()
      }
      return
    }
    startAudio()
  }

  private func handleTransportEnded() {
    if isSystemCall {
      connect.transportDidEnd()
      return
    }
    stopAudio()
  }

  private func startSystemAudio() {
    isSystemAudioActive = true
    guard isSystemCall, !audio.isActive else { return }
    startAudio()
  }

  private func activateRoute() throws {
    if isSystemCall {
      try routes.adopt()
    } else {
      try routes.activate(proximityRouting: !isTestingMic)
    }
  }

  private func deactivateRoute() {
    guard !isSystemCall else {
      routes.stopProximityRouting()
      return
    }
    routes.deactivate()
  }

  /// The system stops the engine and deactivates the session when another app
  /// takes it, and never gives it back on its own. Stopping cleanly also ends
  /// the engine's own restart attempts, which cannot succeed while the session
  /// belongs to somebody else.
  private func handleInterruption(began: Bool) {
    guard isInCall || isTesting else { return }
    if began {
      // The session is already gone by the time this arrives, so stopping is
      // bookkeeping, not a choice. A call should not lose to another app's
      // audio though, so ask for the session straight back, which stops
      // whatever took it. A test is not worth fighting for.
      log("call audio interrupted, stopping engine")
      audio.stop()
      guard isInCall else { return }
      resumeAudio(attempt: 1)
      return
    }
    resumeAudio(attempt: 1)
  }

  private func resumeAudio(attempt: Int) {
    guard isInCall || isTesting, !audio.isActive else { return }
    do {
      try activateRoute()
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
    guard isInCall || isTesting, !audio.isActive else { return }
    log("call audio stopped on foreground, resuming")
    resumeAudio(attempt: 1)
  }

  func requestMicPermission() async {
    let granted = await RecordingPermission.hasPermissionToRecord()
    micPermissionDenied = !granted
    log("call mic permission", granted)
  }

  func startMicTest() {
    guard !isInCall else { return }
    stopTests()
    log("mic test starting")
    do {
      try routes.activate(proximityRouting: false)
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

  func startSpeakerTest() {
    guard !isInCall else { return }
    stopTests()
    log("speaker test starting")
    do {
      try routes.activate()
      try audio.start()
      isMuted = false
      isTestingSpeaker = true
      startLevelPolling()
      startSpeakerTone()
    } catch {
      log("failed to start speaker test", error)
      audio.stop()
      routes.deactivate()
    }
  }

  func stopSpeakerTest() {
    guard isTestingSpeaker else { return }
    log("speaker test stopped", playbackSummary())
    isTestingSpeaker = false
    speakerToneTask?.cancel()
    speakerToneTask = nil
    audio.stop()
    routes.deactivate()
    stopLevelPolling()
  }

  private func stopTests() {
    stopMicTest()
    stopSpeakerTest()
  }

  private func startSpeakerTone() {
    let packets = SpeakerTestTone.packets()
    guard !packets.isEmpty else { return }
    speakerToneTask?.cancel()
    speakerToneTask = Task { [weak self] in
      let startedAt = Date()
      var sent = 0
      while !Task.isCancelled {
        guard let self, self.isTestingSpeaker else { return }
        // Packets are due on the wall clock, kept the same fraction of a
        // second ahead a call runs at. Sending one per fixed sleep drifts
        // late and starves the player instead.
        let due = Int((Date().timeIntervalSince(startedAt) + 0.1) / SpeakerTestTone.packetSeconds)
        while sent < due {
          self.audio.playIncoming(seq: UInt32(sent), data: packets[sent % packets.count])
          sent += 1
        }
        try? await Task.sleep(for: .milliseconds(20))
      }
    }
  }

  private func startAudio() {
    log("call audio starting")
    stopTests()
    do {
      try activateRoute()
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
      deactivateRoute()
      isInCall = false
      transport.disconnect(statusMessage: "Connected, but audio failed to start: \(error.localizedDescription)")
    }
  }

  /// The chime plays through the call's engine and route, so the engine is
  /// only torn down once it has finished. The timeout covers a chime that
  /// never reports back, e.g. when the route dies with the call.
  private func stopAudio() {
    log("call audio stopping", transport.callStateSummary(), playbackSummary())
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
    guard !isInCall, !isTesting else { return }
    audio.stop()
    deactivateRoute()
  }

  private func playbackSummary() -> String {
    let stats = audio.playbackStats()
    return String(
      format:
        "playback backlog=%dms received=%dms skipped=%dms resyncs=%d arrivalRate=%.2f lost=%dms late=%d noise=%dms",
      stats.backlogMs, stats.receivedMs, stats.skippedMs, stats.resyncs, stats.arrivalRate,
      stats.lostMs, stats.lateFrames, stats.noiseMs)
  }

  private func startStatsLogging() {
    statsTask?.cancel()
    statsTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(10))
        guard let self, self.isInCall else { return }
        let arrivals = self.audio.takeArrivalStats()
        log(
          "call stats", self.transport.callStateSummary(), self.playbackSummary(),
          String(
            format: "arrivalGapMax=%dms backlogMin=%dms backlogMax=%dms captureMax=%dms",
            arrivals.maxGapMs, arrivals.minBacklogMs, arrivals.maxBacklogMs,
            arrivals.captureMaxMs))
      }
    }
  }

  private func stopLevelPolling() {
    levelTask?.cancel()
    levelTask = nil
    inputLevel = 0
    outputLevel = 0
    networkRttMs = nil
    endToEndMs = nil
    downKbps = nil
    upKbps = nil
    lastBytesSample = nil
  }

  private func startLevelPolling() {
    levelTask?.cancel()
    levelTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(100))
        guard let self else { return }
        let taken = self.audio.takeLevels()
        self.inputLevel = max(min(1, taken.input.squareRoot()), self.inputLevel * 0.7)
        self.outputLevel = max(min(1, taken.output.squareRoot()), self.outputLevel * 0.7)
        self.updateNetworkStats()
      }
    }
  }

  private func updateNetworkStats() {
    guard let stats = transport.networkStats() else {
      networkRttMs = nil
      endToEndMs = nil
      downKbps = nil
      upKbps = nil
      lastBytesSample = nil
      return
    }
    networkRttMs = stats.rttMs
    let now = Date()
    guard let last = lastBytesSample else {
      lastBytesSample = (now, stats.sentBytes, stats.receivedBytes)
      return
    }
    let elapsed = now.timeIntervalSince(last.at)
    guard elapsed >= 1 else { return }
    // Peer capture + half a 20ms packet + half the round trip + local playout. Assumes a symmetric
    // path.
    endToEndMs = stats.rttMs.map { rtt in
      stats.peerCaptureMs + 10 + rtt / 2 + audio.playoutDelayMs()
    }
    upKbps = Int(Double((stats.sentBytes - last.sent) * 8) / elapsed / 1000)
    downKbps = Int(Double((stats.receivedBytes - last.received) * 8) / elapsed / 1000)
    lastBytesSample = (now, stats.sentBytes, stats.receivedBytes)
  }

  func endCall() {
    if isSystemCall {
      // CallKit has to end it, or the system call UI outlives the call.
      connect.endCall()
      return
    }
    transport.disconnect()
    stopAudio()
  }
}

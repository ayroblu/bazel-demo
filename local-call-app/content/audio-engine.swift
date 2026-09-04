import AVFoundation
import Log

#if os(macOS)
import CoreAudio
#endif

nonisolated final class CallAudioEngine: @unchecked Sendable {
  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  /// Plays the queue slightly fast to catch up without dropping anything.
  /// Rate here is tempo only, the unit keeps the pitch, so a caught-up voice
  /// sounds hurried rather than squeaky.
  private let timePitch = AVAudioUnitTimePitch()
  private let transportSampleRate = 16000.0
  private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
  private var isRunning = false
  var isActive: Bool { isRunning }
  private var configChangeObserver: NSObjectProtocol?

  #if os(iOS)
  private var routeChangeObserver: NSObjectProtocol?
  private var pendingRouteRestart: DispatchWorkItem?
  #endif

  #if os(macOS)
  // nil means follow the current system default device.
  private var preferredInputID: AudioDeviceID?
  private var preferredOutputID: AudioDeviceID?
  #endif

  var onOutgoingAudio: (@Sendable (Data) -> Void)?
  var isMuted = false

  private let levelLock = NSLock()
  private var inputPeak: Float = 0
  private var outputPeak: Float = 0

  // An AVAudioPlayerNode plays its queue in order and never catches up, so a
  // network stall or a clock difference is added to the mouth-to-ear delay
  // and stays there. Rather than shedding audio continuously, playback runs
  // untouched until the delay passes this much, then skips straight to the
  // newest audio: one discontinuity instead of permanent chop.
  private let maxBacklogFrames = 16000  // 1s at 16kHz
  /// Below this the queue is normal jitter and is left alone.
  private let catchUpFromFrames = 3200  // 200ms at 16kHz
  private let maxCatchUpRate: Float = 1.08
  private let playbackLock = NSLock()
  private var scheduledFrames = 0
  private var receivedFrames = 0
  private var skippedFrames = 0
  private var resyncCount = 0
  private var firstIncomingAt: Date?
  private var lastStoppedLogAt: Date?
  private var lastRateLogAt: Date?

  /// Snapshot of the playback queue for the periodic call log. `arrivalRate`
  /// is incoming audio seconds per elapsed second: above 1.0 the peer is
  /// producing faster than real time, which no amount of buffering can fix.
  func playbackStats() -> (
    backlogMs: Int, receivedMs: Int, skippedMs: Int, resyncs: Int, arrivalRate: Double
  ) {
    let backlog = backlogFrames()
    playbackLock.lock()
    defer { playbackLock.unlock() }
    let msPerFrame = 1000.0 / transportSampleRate
    let receivedMs = Double(receivedFrames) * msPerFrame
    let elapsedMs = firstIncomingAt.map { Date().timeIntervalSince($0) * 1000 } ?? 0
    return (
      Int(Double(backlog) * msPerFrame),
      Int(receivedMs),
      Int(Double(skippedFrames) * msPerFrame),
      resyncCount,
      elapsedMs > 1000 ? receivedMs / elapsedMs : 0
    )
  }

  /// Frames scheduled but not yet rendered. Taken from the render clock
  /// rather than scheduleBuffer completions, which report back a whole output
  /// latency late and made the queue look permanently overfull on Bluetooth.
  private func backlogFrames() -> Int {
    guard let nodeTime = playerNode.lastRenderTime, nodeTime.isSampleTimeValid,
      let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
    else { return 0 }
    playbackLock.lock()
    defer { playbackLock.unlock() }
    return max(0, scheduledFrames - Int(playerTime.sampleTime))
  }

  /// Peak levels (0...1) accumulated since the last call; reading resets
  /// them, so a silent or stopped stream naturally reads as zero.
  func takeLevels() -> (input: Float, output: Float) {
    levelLock.lock()
    defer { levelLock.unlock() }
    let levels = (inputPeak, outputPeak)
    inputPeak = 0
    outputPeak = 0
    return levels
  }

  init() {
    engine.attach(playerNode)
    engine.attach(timePitch)
    // AVFoundation stops the engine and posts this when the active device's
    // hardware format changes or the device goes away entirely (e.g. AirPods
    // connect or disconnect mid-call). Without a restart the call goes
    // permanently silent in both directions.
    configChangeObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in
      guard let self, self.isRunning else { return }
      #if os(iOS)
      // During Bluetooth HFP negotiation this notification arrives before
      // inputNode reports the settled hardware format. Restarting immediately
      // can install a 48 kHz tap while the AirPods mic has moved to 24 kHz.
      self.scheduleRouteRestart()
      #else
      log("audio engine configuration change, restarting")
      self.restart()
      #endif
    }
    #if os(iOS)
    routeChangeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      guard let self, self.isRunning else { return }
      self.scheduleRouteRestart()
    }
    #endif
  }

  deinit {
    if let configChangeObserver {
      NotificationCenter.default.removeObserver(configChangeObserver)
    }
    #if os(iOS)
    if let routeChangeObserver {
      NotificationCenter.default.removeObserver(routeChangeObserver)
    }
    pendingRouteRestart?.cancel()
    #endif
  }

  func start() throws {
    guard !isRunning else { return }
    isRunning = true
    do {
      try startEngine()
    } catch {
      isRunning = false
      throw error
    }
  }

  func stop() {
    guard isRunning else { return }
    isRunning = false
    #if os(iOS)
    pendingRouteRestart?.cancel()
    pendingRouteRestart = nil
    #endif
    tearDownEngine()
  }

  #if os(iOS)
  /// Coalesces the configuration and route notifications emitted while a
  /// Bluetooth input negotiates HFP, then rebuilds the tap after the route's
  /// hardware format has settled.
  private func scheduleRouteRestart() {
    pendingRouteRestart?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.isRunning else { return }
      self.pendingRouteRestart = nil
      let route = AVAudioSession.sharedInstance().currentRoute
      log(
        "audio route settled, restarting engine",
        route.inputs.map { $0.portName }.joined(separator: ","))
      self.restart()
    }
    pendingRouteRestart = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
  }
  #endif

  #if os(macOS)
  /// Pin the engine to specific devices, or pass nil to follow the system
  /// default. Restarts the engine only when the effective device changes.
  func setPreferredDevices(input: AudioDeviceID?, output: AudioDeviceID?) {
    preferredInputID = input
    preferredOutputID = output
    guard isRunning else { return }
    let effectiveInput = input ?? MacAudio.defaultDeviceID(input: true)
    let effectiveOutput = output ?? MacAudio.defaultDeviceID(input: false)
    if engine.inputNode.auAudioUnit.deviceID == effectiveInput
      && engine.outputNode.auAudioUnit.deviceID == effectiveOutput
    {
      return
    }
    log("audio devices changed, restarting", effectiveInput ?? 0, effectiveOutput ?? 0)
    restart()
  }

  private func applyPreferredDevices() {
    let input = preferredInputID ?? MacAudio.defaultDeviceID(input: true)
    let output = preferredOutputID ?? MacAudio.defaultDeviceID(input: false)
    if let input, engine.inputNode.auAudioUnit.deviceID != input {
      do {
        try engine.inputNode.auAudioUnit.setDeviceID(input)
      } catch {
        log("failed to set input device", input, error)
      }
    }
    if let output, engine.outputNode.auAudioUnit.deviceID != output {
      do {
        try engine.outputNode.auAudioUnit.setDeviceID(output)
      } catch {
        log("failed to set output device", output, error)
      }
    }
  }
  #endif

  private func startEngine() throws {
    #if os(macOS)
    applyPreferredDevices()
    warnIfMacInputMuted(deviceID: engine.inputNode.auAudioUnit.deviceID)
    #endif
    engine.connect(playerNode, to: timePitch, format: playbackFormat)
    engine.connect(timePitch, to: engine.mainMixerNode, format: playbackFormat)
    // The input format must be re-read on every (re)start: it changes when
    // the route changes (e.g. built-in mic at 48kHz vs AirPods HFP).
    let nodeFormat = engine.inputNode.outputFormat(forBus: 0)
    #if os(iOS)
    // inputNode can keep reporting its previous client rate briefly after the
    // session has switched hardware (48 kHz here while AirPods are at 24 kHz).
    // A tap on an input node must use the hardware rate or AVAudioEngine rejects
    // it with "Format mismatch: input hw ..., client format ...".
    let session = AVAudioSession.sharedInstance()
    let hardwareSampleRate = session.sampleRate
    let hardwareChannels = AVAudioChannelCount(session.inputNumberOfChannels)
    guard hardwareSampleRate > 0, hardwareChannels > 0,
      let inputFormat = AVAudioFormat(
        standardFormatWithSampleRate: hardwareSampleRate, channels: hardwareChannels)
    else {
      throw CallAudioError.routeNotReady
    }
    log(
      "audio engine input format", inputFormat.sampleRate, inputFormat.channelCount,
      "node reported", nodeFormat.sampleRate, nodeFormat.channelCount)
    #else
    let inputFormat = nodeFormat
    log("audio engine input format", inputFormat.sampleRate, inputFormat.channelCount)
    guard inputFormat.sampleRate > 0 else {
      throw CallAudioError.noInput
    }
    #endif
    engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) {
      [weak self] buffer, _ in
      self?.handleMicBuffer(buffer)
    }
    engine.prepare()
    do {
      try engine.start()
    } catch {
      log("audio engine start failed", error)
      engine.inputNode.removeTap(onBus: 0)
      throw error
    }
    playerNode.play()
    // The time pitch unit buys catch up at the cost of its own latency, so
    // it is worth seeing what that costs on real hardware.
    log(
      "audio engine running", engine.isRunning, "player", playerNode.isPlaying,
      "time pitch latency", timePitch.latency)
  }

  private func tearDownEngine() {
    resetPlayback()
    playerNode.stop()
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    #if os(iOS)
    // Discard the graph's cached input format before rebuilding it for a new
    // AVAudioSession route.
    engine.reset()
    #endif
  }

  private func restart() {
    tearDownEngine()
    do {
      try startEngine()
    } catch {
      #if os(iOS)
      guard isRunning else { return }
      log("audio engine restart waiting for route", error)
      scheduleRouteRestart()
      #else
      log("audio engine restart failed", error)
      #endif
    }
  }

  private func handleMicBuffer(_ buffer: AVAudioPCMBuffer) {
    guard !isMuted, let onOutgoingAudio else { return }
    guard let floatChannel = buffer.floatChannelData, buffer.frameLength > 0 else { return }

    let inputFrames = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    let outputFrames = max(1, Int(Double(inputFrames) * transportSampleRate / buffer.format.sampleRate))
    var samples = [Int16](repeating: 0, count: outputFrames)
    var peak: Float = 0

    for outputIndex in 0..<outputFrames {
      let inputIndex = min(inputFrames - 1, Int(Double(outputIndex) * buffer.format.sampleRate / transportSampleRate))
      var monoSample: Float = 0
      for channelIndex in 0..<channelCount {
        monoSample += floatChannel[channelIndex][inputIndex]
      }
      monoSample /= Float(max(1, channelCount))
      let clamped = max(-1, min(1, monoSample))
      peak = max(peak, abs(clamped))
      samples[outputIndex] = Int16(clamped * Float(Int16.max))
    }

    levelLock.lock()
    inputPeak = max(inputPeak, peak)
    levelLock.unlock()

    onOutgoingAudio(samples.withUnsafeBytes { Data($0) })
  }

  func playIncoming(_ data: Data) {
    guard isRunning else {
      // Audio arriving while the engine is down is silent by definition, and
      // has to be visible or it looks the same as a peer sending nothing.
      playbackLock.lock()
      let shouldLog = shouldLogLocked(&lastStoppedLogAt)
      playbackLock.unlock()
      if shouldLog {
        log("received audio while engine stopped, discarding", data.count)
      }
      return
    }
    let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
    guard frameCount > 0 else { return }
    noteIncoming(frames: Int(frameCount))
    skipAheadIfBehind()
    adjustCatchUpRate()
    guard let outBuffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount)
    else { return }
    outBuffer.frameLength = frameCount
    guard let floatChannel = outBuffer.floatChannelData else { return }
    var peak: Float = 0
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      let samples = raw.bindMemory(to: Int16.self)
      for i in 0..<Int(frameCount) {
        let sample = Float(samples[i]) / Float(Int16.max)
        peak = max(peak, abs(sample))
        floatChannel.pointee[i] = sample
      }
    }
    levelLock.lock()
    outputPeak = max(outputPeak, peak)
    levelLock.unlock()
    playerNode.scheduleBuffer(outBuffer)
    playbackLock.lock()
    scheduledFrames += Int(frameCount)
    playbackLock.unlock()
  }

  private func noteIncoming(frames: Int) {
    playbackLock.lock()
    receivedFrames += frames
    if firstIncomingAt == nil {
      firstIncomingAt = Date()
    }
    playbackLock.unlock()
  }

  /// Stopping the player flushes everything still queued and resets its
  /// render clock, so playback carries on from the audio that arrives next:
  /// the delay collapses back to nothing in one step.
  /// Catching up by playing faster keeps every word, but only works on a
  /// backlog worth seconds at most: at 1.08x a five second stall would take
  /// a minute to absorb, so anything past a second is skipped instead.
  private func adjustCatchUpRate() {
    let backlog = backlogFrames()
    let excess = Float(backlog - catchUpFromFrames)
    let span = Float(maxBacklogFrames - catchUpFromFrames)
    let rate =
      excess <= 0 ? 1 : 1 + min(maxCatchUpRate - 1, (excess / span) * (maxCatchUpRate - 1))
    guard abs(rate - timePitch.rate) > 0.005 else { return }
    timePitch.rate = rate
    playbackLock.lock()
    let shouldLog = shouldLogLocked(&lastRateLogAt)
    playbackLock.unlock()
    if shouldLog {
      log(
        "playback catch up rate", rate, "backlog",
        Int(Double(backlog) * 1000 / transportSampleRate), "ms")
    }
  }

  private func skipAheadIfBehind() {
    let backlog = backlogFrames()
    guard backlog > maxBacklogFrames else { return }
    playerNode.stop()
    playerNode.play()
    timePitch.rate = 1
    playbackLock.lock()
    scheduledFrames = 0
    skippedFrames += backlog
    resyncCount += 1
    let count = resyncCount
    playbackLock.unlock()
    log(
      "playback skipped ahead", Int(Double(backlog) * 1000 / transportSampleRate), "ms behind",
      "resyncs", count)
  }

  /// Plays the disconnect chime through the call's own route, ahead of
  /// whatever incoming audio is still queued, and reports back when it has
  /// finished so the caller can tear the engine down afterwards.
  func playChime(completion: @escaping @Sendable () -> Void) {
    guard isRunning, let buffer = makeChimeBuffer(format: playbackFormat) else {
      completion()
      return
    }
    resetPlayback()
    playerNode.stop()
    playerNode.play()
    playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
      completion()
    }
  }

  /// Buffers already scheduled are flushed when the node stops, and the
  /// render clock restarts, so the queue accounting starts over with it.
  private func resetPlayback() {
    timePitch.rate = 1
    playbackLock.lock()
    scheduledFrames = 0
    playbackLock.unlock()
  }

  private func shouldLogLocked(_ lastLoggedAt: inout Date?) -> Bool {
    let now = Date()
    if let lastLoggedAt, now.timeIntervalSince(lastLoggedAt) < 5 {
      return false
    }
    lastLoggedAt = now
    return true
  }
}

enum CallAudioError: Error {
  case noInput
  case routeNotReady
}

enum RecordingPermission {
  static func hasPermissionToRecord() async -> Bool {
    #if os(macOS)
    let granted = await AVCaptureDevice.requestAccess(for: .audio)
    #else
    let granted = await withCheckedContinuation { continuation in
      AVAudioApplication.requestRecordPermission { authorized in
        continuation.resume(returning: authorized)
      }
    }
    #endif
    log("recording permission", granted)
    return granted
  }
}

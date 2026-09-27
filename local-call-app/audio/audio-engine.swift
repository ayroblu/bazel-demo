import AVFoundation
import Log

public nonisolated final class CallAudioEngine: @unchecked Sendable {
  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  /// Plays the queue slightly fast to catch up without dropping anything.
  /// Varispeed is a plain rate converter, so unlike a time pitch unit it adds
  /// no processing latency of its own; the cost is that catching up raises
  /// the pitch by up to 8%, briefly, which is less noticeable than the delay.
  private let varispeed = AVAudioUnitVarispeed()
  private let playbackFormat = AVAudioFormat(
    standardFormatWithSampleRate: OpusCall.sampleRate, channels: 1)!
  private let encoder = OpusEncoder()
  private let decoder = OpusDecoder()
  private let jitter = JitterBuffer()
  private let catchUp = CatchUpController()
  private let queue = PlaybackQueue()
  private var isRunning = false
  public var isActive: Bool { isRunning }
  private var configChangeObserver: NSObjectProtocol?

  private var routeChangeObserver: NSObjectProtocol?
  private var pendingRouteRestart: DispatchWorkItem?

  /// A second without incoming audio switches playback to quiet white noise
  /// until audio arrives again, so a silent peer still sounds like a live
  /// line. It only runs once a call has produced audio: a mic test receives
  /// nothing and should stay silent.
  private let comfortNoiseDelay: TimeInterval = 1
  private let noiseQueue = DispatchQueue(label: "call-audio-noise", qos: .userInitiated)
  private var noiseTimer: DispatchSourceTimer?

  /// Called with one encoded 20ms opus frame at a time.
  public var onOutgoingAudio: (@Sendable (Data) -> Void)?
  public var isMuted = false

  private let levelLock = NSLock()
  private var inputPeak: Float = 0
  private var outputPeak: Float = 0

  private let micLock = NSLock()
  private var micPending: [Float] = []

  // An AVAudioPlayerNode plays its queue in order and never catches up, so a
  // network stall or a clock difference is added to the mouth-to-ear delay
  // and stays there. Rather than shedding audio continuously, playback runs
  // untouched until the delay passes this much, then skips straight to the
  // newest audio: one discontinuity instead of permanent chop.
  private let maxBacklogFrames = 16000  // 1s at 16kHz
  private let playbackLock = NSLock()
  private var receivedFrames = 0
  private var skippedFrames = 0
  private var resyncCount = 0
  private var firstIncomingAt: Date?
  private var lastIncomingAt: Date?
  private var noiseFrames = 0
  private var windowMaxGapMs = 0
  private var windowMinBacklogMs = Int.max
  private var windowMaxBacklogMs = 0
  private var windowMaxCaptureDelayMs = 0
  private var lastStoppedLogAt: Date?
  private var lastRateLogAt: Date?
  private var lastNoiseLogAt: Date?

  /// Snapshot of the playback queue for the periodic call log. `arrivalRate`
  /// is incoming audio seconds per elapsed second: above 1.0 the peer is
  /// producing faster than real time, which no amount of buffering can fix.
  public func playbackStats() -> (
    backlogMs: Int, receivedMs: Int, skippedMs: Int, resyncs: Int, arrivalRate: Double,
    lostMs: Int, lateFrames: Int, noiseMs: Int
  ) {
    let backlog = backlogFrames()
    let jitterStats = jitter.stats()
    playbackLock.lock()
    defer { playbackLock.unlock() }
    let msPerFrame = 1000.0 / OpusCall.sampleRate
    let receivedMs = Double(receivedFrames) * msPerFrame
    let elapsedMs = firstIncomingAt.map { Date().timeIntervalSince($0) * 1000 } ?? 0
    return (
      Int(Double(backlog) * msPerFrame),
      Int(receivedMs),
      Int(Double(skippedFrames) * msPerFrame),
      resyncCount,
      elapsedMs > 1000 ? receivedMs / elapsedMs : 0,
      Int(Double(jitterStats.lost * OpusCall.frameSamples) * msPerFrame),
      jitterStats.late,
      Int(Double(noiseFrames) * msPerFrame)
    )
  }

  /// Frames scheduled but not yet rendered. Taken from the render clock
  /// rather than scheduleBuffer completions, which report back a whole output
  /// latency late and made the queue look permanently overfull on Bluetooth.
  private func backlogFrames() -> Int {
    guard let nodeTime = playerNode.lastRenderTime, nodeTime.isSampleTimeValid,
      let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
    else { return 0 }
    // The player timeline should already run at the transport rate, but a
    // clock in hardware-rate units would silently zero the backlog reading
    // (constant re-basing), hiding standing delay from catch up entirely.
    var rendered = Int(playerTime.sampleTime)
    if playerTime.sampleRate > 0, playerTime.sampleRate != OpusCall.sampleRate {
      rendered = Int(Double(rendered) * OpusCall.sampleRate / playerTime.sampleRate)
    }
    return queue.backlog(renderedFrames: rendered)
  }

  /// Arrival pattern since the last read (reading resets it), for the call
  /// heartbeat. The radio's true character lives in the extremes, which the
  /// instantaneous backlog number never shows: a large `maxGapMs` with a low
  /// `minBacklogMs` means the link delivers in bursts and the queue depth is
  /// forced by the burst period, not by anything this side can drain.
  /// `captureMaxMs` is the other end of the pipe: hardware capture time to
  /// the mic tap, which is where the voice processing unit's delay hides.
  public func takeArrivalStats() -> (
    maxGapMs: Int, minBacklogMs: Int, maxBacklogMs: Int, captureMaxMs: Int
  ) {
    playbackLock.lock()
    defer { playbackLock.unlock() }
    let stats = (
      windowMaxGapMs, windowMinBacklogMs == .max ? 0 : windowMinBacklogMs, windowMaxBacklogMs,
      windowMaxCaptureDelayMs
    )
    windowMaxGapMs = 0
    windowMinBacklogMs = .max
    windowMaxBacklogMs = 0
    windowMaxCaptureDelayMs = 0
    return stats
  }

  /// Peak levels (0...1) accumulated since the last call; reading resets
  /// them, so a silent or stopped stream naturally reads as zero.
  public func takeLevels() -> (input: Float, output: Float) {
    levelLock.lock()
    defer { levelLock.unlock() }
    let levels = (inputPeak, outputPeak)
    inputPeak = 0
    outputPeak = 0
    return levels
  }

  public init() {
    engine.attach(playerNode)
    engine.attach(varispeed)
    if encoder == nil || decoder == nil {
      log("audio opus codec unavailable")
    }
    // AVFoundation stops the engine and posts this when the active device's
    // hardware format changes or the device goes away entirely (e.g. AirPods
    // connect or disconnect mid-call). Without a restart the call goes
    // permanently silent in both directions.
    configChangeObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in
      guard let self, self.isRunning else { return }
      // During Bluetooth HFP negotiation this notification arrives before
      // inputNode reports the settled hardware format. Restarting immediately
      // can install a 48 kHz tap while the AirPods mic has moved to 24 kHz.
      self.scheduleRouteRestart()
    }
    routeChangeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      guard let self, self.isRunning else { return }
      self.scheduleRouteRestart()
    }
  }

  deinit {
    if let configChangeObserver {
      NotificationCenter.default.removeObserver(configChangeObserver)
    }
    if let routeChangeObserver {
      NotificationCenter.default.removeObserver(routeChangeObserver)
    }
    pendingRouteRestart?.cancel()
  }

  public func start() throws {
    guard !isRunning else { return }
    isRunning = true
    do {
      try startEngine()
    } catch {
      isRunning = false
      throw error
    }
  }

  public func stop() {
    guard isRunning else { return }
    isRunning = false
    pendingRouteRestart?.cancel()
    pendingRouteRestart = nil
    tearDownEngine()
  }

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

  private func startEngine() throws {
    let input = engine.inputNode
    enableVoiceProcessing(on: input)
    engine.connect(playerNode, to: varispeed, format: playbackFormat)
    engine.connect(varispeed, to: engine.mainMixerNode, format: playbackFormat)
    // The input format must be re-read on every (re)start: it changes when
    // the route changes (e.g. built-in mic at 48kHz vs AirPods HFP), and with
    // voice processing it belongs to the processing unit rather than the
    // hardware, so the node is the only source that matches the tap.
    let inputFormat = input.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
      throw CallAudioError.routeNotReady
    }
    let session = AVAudioSession.sharedInstance()
    log(
      "audio engine input format", inputFormat.sampleRate, inputFormat.channelCount,
      "session", session.sampleRate, session.inputNumberOfChannels,
      "io buffer", session.ioBufferDuration,
      "hw latency in", session.inputLatency, "out", session.outputLatency,
      "voice processing", input.isVoiceProcessingEnabled,
      "agc", input.isVoiceProcessingAGCEnabled)
    micLock.lock()
    micPending = []
    micLock.unlock()
    // A small tap so capture adds ~10ms of batching rather than the ~43ms a
    // 2048 frame tap did; frames are cut to 20ms packets downstream anyway.
    input.installTap(onBus: 0, bufferSize: 512, format: inputFormat) {
      [weak self] buffer, when in
      self?.handleMicBuffer(buffer, at: when)
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
    playbackLock.lock()
    lastIncomingAt = nil
    playbackLock.unlock()
    startComfortNoise()
    log(
      "audio engine running", engine.isRunning, "player", playerNode.isPlaying,
      "varispeed latency", varispeed.latency)
  }

  private func startComfortNoise() {
    stopComfortNoise()
    let timer = DispatchSource.makeTimerSource(queue: noiseQueue)
    timer.schedule(deadline: .now() + comfortNoiseDelay, repeating: .milliseconds(20))
    timer.setEventHandler { [weak self] in
      self?.scheduleComfortNoiseIfStarved()
    }
    timer.activate()
    noiseTimer = timer
  }

  private func stopComfortNoise() {
    noiseTimer?.cancel()
    noiseTimer = nil
  }

  /// Feeds the player 20ms of noise at a time, and only while it is nearly
  /// starved, so resuming audio finds at most ~60ms of noise queued ahead of
  /// it rather than a backlog of it.
  private func scheduleComfortNoiseIfStarved() {
    guard isRunning else { return }
    playbackLock.lock()
    let last = lastIncomingAt
    playbackLock.unlock()
    guard let last, Date().timeIntervalSince(last) > comfortNoiseDelay else { return }
    guard backlogFrames() < OpusCall.frameSamples * 3 else { return }
    schedule(samples: ComfortNoise.frame(samples: OpusCall.frameSamples), metersLevel: false)
    playbackLock.lock()
    noiseFrames += OpusCall.frameSamples
    let shouldLog = shouldLogLocked(&lastNoiseLogAt)
    playbackLock.unlock()
    if shouldLog {
      log("playing comfort noise, no incoming audio", Date().timeIntervalSince(last))
    }
  }

  /// Voice processing is the only way to get the system's echo cancellation
  /// and automatic gain control, and it can only be switched while the engine
  /// is stopped. Enabling it on the input node enables it on the output too.
  /// A call without it is quiet and echoes, but still works, so a failure
  /// here is not fatal.
  private func enableVoiceProcessing(on input: AVAudioInputNode) {
    guard !input.isVoiceProcessingEnabled else { return }
    do {
      try input.setVoiceProcessingEnabled(true)
    } catch {
      log("audio voice processing unavailable", error)
    }
  }

  private func tearDownEngine() {
    stopComfortNoise()
    resetPlayback()
    playerNode.stop()
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    // Discard the graph's cached input format before rebuilding it for a new
    // AVAudioSession route.
    engine.reset()
  }

  private func restart() {
    tearDownEngine()
    do {
      try startEngine()
    } catch {
      guard isRunning else { return }
      log("audio engine restart waiting for route", error)
      scheduleRouteRestart()
    }
  }

  private func handleMicBuffer(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime) {
    // The tap timestamp is when the first sample left the hardware, so the
    // difference to now is the whole capture pipeline, voice processing
    // included - the one mouth-to-ear segment no session property reports.
    if when.isHostTimeValid {
      let capturedAt = AVAudioTime.seconds(forHostTime: when.hostTime)
      let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
      let delayMs = Int((now - capturedAt) * 1000)
      if delayMs >= 0, delayMs < 5000 {
        playbackLock.lock()
        windowMaxCaptureDelayMs = max(windowMaxCaptureDelayMs, delayMs)
        playbackLock.unlock()
      }
    }
    guard !isMuted, let onOutgoingAudio, let encoder else { return }
    guard let floatChannel = buffer.floatChannelData, buffer.frameLength > 0 else { return }

    let inputFrames = Int(buffer.frameLength)
    let outputFrames = max(
      1, Int(Double(inputFrames) * OpusCall.sampleRate / buffer.format.sampleRate))
    var samples = [Float](repeating: 0, count: outputFrames)
    var peak: Float = 0
    // Voice processing adds channels carrying its own echo cancellation data.
    // Channel 0 is the audio; mixing the others in would corrupt it.
    let source = floatChannel[0]

    for outputIndex in 0..<outputFrames {
      let inputIndex = min(
        inputFrames - 1, Int(Double(outputIndex) * buffer.format.sampleRate / OpusCall.sampleRate))
      let clamped = max(-1, min(1, source[inputIndex]))
      peak = max(peak, abs(clamped))
      samples[outputIndex] = clamped
    }

    levelLock.lock()
    inputPeak = max(inputPeak, peak)
    levelLock.unlock()

    // The tap hands over whatever the hardware granularity is; the wire
    // carries exact 20ms frames, so the remainder waits for the next buffer.
    micLock.lock()
    micPending.append(contentsOf: samples)
    var frames: [[Float]] = []
    while micPending.count >= OpusCall.frameSamples {
      frames.append(Array(micPending.prefix(OpusCall.frameSamples)))
      micPending.removeFirst(OpusCall.frameSamples)
    }
    micLock.unlock()

    for frame in frames {
      guard let payload = encoder.encode(frame) else { continue }
      onOutgoingAudio(payload)
    }
  }

  public func playIncoming(seq: UInt32, data: Data) {
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
    guard let decoder, let samples = decoder.decode(data), !samples.isEmpty else { return }
    noteIncoming(frames: samples.count)
    skipAheadIfBehind()
    let placement = jitter.push(seq: seq)
    if placement.fillFrames > 0 {
      schedule(
        samples: [Float](repeating: 0, count: placement.fillFrames * OpusCall.frameSamples),
        metersLevel: false)
    }
    guard placement.play else { return }
    schedule(samples: samples, metersLevel: true)
    adjustCatchUpRate()
    noteBacklogExtremes()
  }

  private func schedule(samples: [Float], metersLevel: Bool) {
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(samples.count))
    else { return }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { source in
      buffer.floatChannelData!.pointee.update(from: source.baseAddress!, count: samples.count)
    }
    if metersLevel {
      let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
      levelLock.lock()
      outputPeak = max(outputPeak, peak)
      levelLock.unlock()
    }
    playerNode.scheduleBuffer(buffer)
    queue.noteScheduled(frames: samples.count)
  }

  private func noteIncoming(frames: Int) {
    let now = Date()
    playbackLock.lock()
    receivedFrames += frames
    if let lastIncomingAt {
      windowMaxGapMs = max(windowMaxGapMs, Int(now.timeIntervalSince(lastIncomingAt) * 1000))
    }
    lastIncomingAt = now
    if firstIncomingAt == nil {
      firstIncomingAt = now
    }
    playbackLock.unlock()
  }

  private func noteBacklogExtremes() {
    let backlogMs = Int(Double(backlogFrames()) * 1000 / OpusCall.sampleRate)
    playbackLock.lock()
    windowMinBacklogMs = min(windowMinBacklogMs, backlogMs)
    windowMaxBacklogMs = max(windowMaxBacklogMs, backlogMs)
    playbackLock.unlock()
  }

  private func adjustCatchUpRate() {
    let backlog = backlogFrames()
    let rate = catchUp.record(backlogFrames: backlog)
    guard abs(rate - varispeed.rate) > 0.005 else { return }
    varispeed.rate = rate
    playbackLock.lock()
    let shouldLog = shouldLogLocked(&lastRateLogAt)
    playbackLock.unlock()
    if shouldLog {
      log(
        "playback catch up rate", rate, "backlog",
        Int(Double(backlog) * 1000 / OpusCall.sampleRate), "ms")
    }
  }

  /// Stopping the player flushes everything still queued and resets its
  /// render clock, so playback carries on from the audio that arrives next:
  /// the delay collapses back to nothing in one step. Catching up by playing
  /// faster only works on a backlog worth a few hundred ms, so anything past
  /// a second is skipped instead.
  private func skipAheadIfBehind() {
    let backlog = backlogFrames()
    guard backlog > maxBacklogFrames else { return }
    playerNode.stop()
    playerNode.play()
    varispeed.rate = 1
    catchUp.reset()
    queue.reset()
    playbackLock.lock()
    skippedFrames += backlog
    resyncCount += 1
    let count = resyncCount
    playbackLock.unlock()
    log(
      "playback skipped ahead", Int(Double(backlog) * 1000 / OpusCall.sampleRate), "ms behind",
      "resyncs", count)
  }

  /// Plays the disconnect chime through the call's own route, ahead of
  /// whatever incoming audio is still queued, and reports back when it has
  /// finished so the caller can tear the engine down afterwards.
  public func playChime(completion: @escaping @Sendable () -> Void) {
    guard isRunning, let buffer = makeChimeBuffer(format: playbackFormat) else {
      completion()
      return
    }
    // The chime must not have noise appended behind it while it plays out.
    stopComfortNoise()
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
    varispeed.rate = 1
    catchUp.reset()
    jitter.reset()
    queue.reset()
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
  case routeNotReady
}

public enum RecordingPermission {
  public static func hasPermissionToRecord() async -> Bool {
    let granted = await withCheckedContinuation { continuation in
      AVAudioApplication.requestRecordPermission { authorized in
        continuation.resume(returning: authorized)
      }
    }
    log("recording permission", granted)
    return granted
  }
}

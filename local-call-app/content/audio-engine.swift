import AVFoundation
import Log

#if os(macOS)
import CoreAudio
#endif

nonisolated final class CallAudioEngine: @unchecked Sendable {
  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private let transportSampleRate = 16000.0
  private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
  private var isRunning = false
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

  // An AVAudioPlayerNode plays its queue in order and never catches up, so
  // every network stall or clock difference would otherwise be added to the
  // mouth-to-ear delay permanently. Audio queued past the high water mark is
  // dropped until the backlog is back under the low water mark, which keeps
  // latency bounded at the cost of a glitch when the link misbehaves.
  private let backlogHighWaterFrames = 3200  // 200ms at 16kHz
  private let backlogLowWaterFrames = 1280  // 80ms at 16kHz
  private let playbackLock = NSLock()
  private var pendingFrames = 0
  private var isDroppingBacklog = false
  private var playbackGeneration: UInt64 = 0
  private var droppedFrames = 0
  private var playedFrames = 0
  private var lastBacklogLogAt: Date?
  private var lastStoppedLogAt: Date?

  /// Snapshot of the playback queue for the periodic call log.
  func playbackStats() -> (backlogMs: Int, playedMs: Int, droppedMs: Int) {
    playbackLock.lock()
    defer { playbackLock.unlock() }
    let msPerFrame = 1000.0 / transportSampleRate
    return (
      Int(Double(pendingFrames) * msPerFrame),
      Int(Double(playedFrames) * msPerFrame),
      Int(Double(droppedFrames) * msPerFrame)
    )
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
    engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)
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
    log("audio engine running", engine.isRunning, "player", playerNode.isPlaying)
  }

  private func tearDownEngine() {
    resetBacklog()
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
    guard let generation = reserveBacklog(frames: Int(frameCount)) else { return }
    guard let outBuffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount)
    else {
      releaseBacklog(frames: Int(frameCount), generation: generation)
      return
    }
    outBuffer.frameLength = frameCount
    guard let floatChannel = outBuffer.floatChannelData else {
      releaseBacklog(frames: Int(frameCount), generation: generation)
      return
    }
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
    playerNode.scheduleBuffer(outBuffer, completionCallbackType: .dataPlayedBack) {
      [weak self] _ in
      self?.releaseBacklog(frames: Int(frameCount), generation: generation)
    }
  }

  /// Plays the disconnect chime through the call's own route, ahead of
  /// whatever incoming audio is still queued, and reports back when it has
  /// finished so the caller can tear the engine down afterwards.
  func playChime(completion: @escaping @Sendable () -> Void) {
    guard isRunning, let buffer = makeChimeBuffer(format: playbackFormat) else {
      completion()
      return
    }
    resetBacklog()
    playerNode.stop()
    playerNode.play()
    playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
      completion()
    }
  }

  /// Returns the playback generation the frames were counted against, or nil
  /// when the queue is too far behind and the audio should be dropped.
  private func reserveBacklog(frames: Int) -> UInt64? {
    playbackLock.lock()
    if isDroppingBacklog && pendingFrames <= backlogLowWaterFrames {
      isDroppingBacklog = false
    } else if !isDroppingBacklog && pendingFrames + frames > backlogHighWaterFrames {
      isDroppingBacklog = true
    }
    guard !isDroppingBacklog else {
      droppedFrames += frames
      let shouldLog = shouldLogLocked(&lastBacklogLogAt)
      let backlog = pendingFrames
      let dropped = droppedFrames
      playbackLock.unlock()
      if shouldLog {
        log("playback backlog too high, dropping audio", "backlog", backlog, "dropped", dropped)
      }
      return nil
    }
    pendingFrames += frames
    let generation = playbackGeneration
    playbackLock.unlock()
    return generation
  }

  private func releaseBacklog(frames: Int, generation: UInt64) {
    playbackLock.lock()
    if generation == playbackGeneration {
      pendingFrames = max(0, pendingFrames - frames)
      playedFrames += frames
    }
    playbackLock.unlock()
  }

  /// Buffers already scheduled are flushed when the node stops, and their
  /// completion handlers cannot be trusted to run, so the queue accounting
  /// starts over on a new generation.
  private func resetBacklog() {
    playbackLock.lock()
    playbackGeneration &+= 1
    pendingFrames = 0
    isDroppingBacklog = false
    playbackLock.unlock()
  }

  /// Both dropping paths repeat every 100ms while they last, so each gets its
  /// own 5 second throttle rather than silencing the other.
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

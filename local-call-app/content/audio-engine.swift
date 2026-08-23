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

  #if os(macOS)
  // nil means follow the current system default device.
  private var preferredInputID: AudioDeviceID?
  private var preferredOutputID: AudioDeviceID?
  #endif

  // MCSession .unreliable sends are datagram-like: packets larger than the
  // link MTU (~1400 bytes on peer-to-peer wifi) are silently dropped. macOS
  // ignores the requested tap buffer size and delivers 100ms buffers (1600
  // samples = 3200 bytes at 16kHz), so outgoing audio must be chunked to fit.
  private let maxSamplesPerPacket = 640  // 40ms, 1280 bytes

  var onOutgoingAudio: (@Sendable (Data) -> Void)?
  var isMuted = false

  private let levelLock = NSLock()
  private var inputPeak: Float = 0
  private var outputPeak: Float = 0

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
      log("audio engine configuration change, restarting")
      self.restart()
    }
  }

  deinit {
    if let configChangeObserver {
      NotificationCenter.default.removeObserver(configChangeObserver)
    }
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
    tearDownEngine()
  }

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
    let inputFormat = engine.inputNode.outputFormat(forBus: 0)
    log("audio engine input format", inputFormat.sampleRate, inputFormat.channelCount)
    guard inputFormat.sampleRate > 0 else {
      throw CallAudioError.noInput
    }
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
  }

  private func tearDownEngine() {
    playerNode.stop()
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
  }

  private func restart() {
    tearDownEngine()
    do {
      try startEngine()
    } catch {
      log("audio engine restart failed", error)
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

    var start = 0
    while start < outputFrames {
      let end = min(outputFrames, start + maxSamplesPerPacket)
      let data = samples[start..<end].withUnsafeBytes { Data($0) }
      onOutgoingAudio(data)
      start = end
    }
  }

  func playIncoming(_ data: Data) {
    guard isRunning else { return }
    let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
    guard frameCount > 0 else { return }
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
  }
}

enum CallAudioError: Error {
  case noInput
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

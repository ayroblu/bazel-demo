import AVFoundation
#if os(macOS)
import CoreAudio
#endif
import Log

nonisolated private func pcmLevel(_ samples: [Int16]) -> (peak: Int16, rms: Int) {
  var peak = 0
  var sumSquares = 0.0
  for sample in samples {
    let magnitude = min(Int(Int16.max), abs(Int(sample)))
    peak = max(peak, magnitude)
    let normalized = Double(magnitude) / Double(Int16.max)
    sumSquares += normalized * normalized
  }
  let rms = samples.isEmpty ? 0 : Int(sqrt(sumSquares / Double(samples.count)) * 100)
  return (Int16(peak), rms)
}

nonisolated private func pcmLevel(_ data: Data) -> (peak: Int16, rms: Int) {
  data.withUnsafeBytes { raw in
    let samples = raw.bindMemory(to: Int16.self)
    var peak = 0
    var sumSquares = 0.0
    for sample in samples {
      let magnitude = min(Int(Int16.max), abs(Int(sample)))
      peak = max(peak, magnitude)
      let normalized = Double(magnitude) / Double(Int16.max)
      sumSquares += normalized * normalized
    }
    let rms = samples.isEmpty ? 0 : Int(sqrt(sumSquares / Double(samples.count)) * 100)
    return (Int16(peak), rms)
  }
}

nonisolated final class CallAudioEngine: @unchecked Sendable {
  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private let transportSampleRate = 16000.0
  private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
  private var isRunning = false
  private var outgoingPacketCount = 0
  private var incomingPacketCount = 0

  var onOutgoingAudio: (@Sendable (Data) -> Void)?
  var isMuted = false

  func start() throws {
    guard !isRunning else { return }
    log("audio engine using standard input/output")
    log("audio engine attaching player")
    engine.attach(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)
    let inputFormat = engine.inputNode.outputFormat(forBus: 0)
    log("audio engine input format", inputFormat.sampleRate, inputFormat.channelCount)
    logMacInputDevices()
    guard inputFormat.sampleRate > 0 else {
      throw CallAudioError.noInput
    }
    engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) {
      [weak self] buffer, _ in
      self?.handleMicBuffer(buffer)
    }
    engine.prepare()
    log("audio engine prepared")
    do {
      try engine.start()
    } catch {
      log("audio engine start failed", error)
      engine.inputNode.removeTap(onBus: 0)
      engine.detach(playerNode)
      throw error
    }
    playerNode.play()
    outgoingPacketCount = 0
    incomingPacketCount = 0
    isRunning = true
  }

  func stop() {
    guard isRunning else { return }
    playerNode.stop()
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    engine.detach(playerNode)
    isRunning = false
  }

  private func handleMicBuffer(_ buffer: AVAudioPCMBuffer) {
    guard !isMuted, let onOutgoingAudio else { return }
    guard let floatChannel = buffer.floatChannelData, buffer.frameLength > 0 else {
      log("audio mic buffer missing float channel", buffer.format.commonFormat.rawValue, buffer.frameLength)
      return
    }

    let inputFrames = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    let outputFrames = max(1, Int(Double(inputFrames) * transportSampleRate / buffer.format.sampleRate))
    var samples = [Int16](repeating: 0, count: outputFrames)

    for outputIndex in 0..<outputFrames {
      let inputIndex = min(inputFrames - 1, Int(Double(outputIndex) * buffer.format.sampleRate / transportSampleRate))
      var monoSample: Float = 0
      for channelIndex in 0..<channelCount {
        monoSample += floatChannel[channelIndex][inputIndex]
      }
      monoSample /= Float(max(1, channelCount))
      let clamped = max(-1, min(1, monoSample))
      samples[outputIndex] = Int16(clamped * Float(Int16.max))
    }

    let data = samples.withUnsafeBytes { Data($0) }
    outgoingPacketCount += 1
    if outgoingPacketCount == 1 || outgoingPacketCount % 100 == 0 {
      let level = pcmLevel(samples)
      log(
        "audio outgoing packet", outgoingPacketCount, data.count, "bytes", "inputFrames",
        inputFrames, "outputFrames", outputFrames, "peak", level.peak, "rms", level.rms)
    }
    onOutgoingAudio(data)
  }

  func playIncoming(_ data: Data) {
    guard isRunning else { return }
    incomingPacketCount += 1
    if incomingPacketCount == 1 || incomingPacketCount % 100 == 0 {
      let level = pcmLevel(data)
      log("audio incoming packet", incomingPacketCount, data.count, "bytes", "peak", level.peak, "rms", level.rms)
    }
    let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
    guard frameCount > 0 else { return }
    guard let outBuffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount)
    else { return }
    outBuffer.frameLength = frameCount
    guard let floatChannel = outBuffer.floatChannelData else { return }
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      let samples = raw.bindMemory(to: Int16.self)
      for i in 0..<Int(frameCount) {
        floatChannel.pointee[i] = Float(samples[i]) / Float(Int16.max)
      }
    }
    playerNode.scheduleBuffer(outBuffer) {
      if self.incomingPacketCount == 1 || self.incomingPacketCount % 100 == 0 {
        log("audio playback completed packet", self.incomingPacketCount)
      }
    }
  }
}

enum CallAudioError: Error {
  case noInput
}

enum RecordingPermission {
  static func hasPermissionToRecord() async -> Bool {
    #if os(macOS)
    let granted: Bool
    if #available(macOS 14.0, *) {
      granted = await AVCaptureDevice.requestAccess(for: .audio)
    } else {
      granted = true
    }
    log("recording permission", granted)
    return granted
    #else
    let granted = await withCheckedContinuation { continuation in
      AVAudioApplication.requestRecordPermission { authorized in
        continuation.resume(returning: authorized)
      }
    }
    log("recording permission", granted)
    return granted
    #endif
  }
}

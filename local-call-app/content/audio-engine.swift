import AVFoundation
import Log

nonisolated final class CallAudioEngine: @unchecked Sendable {
  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private let transportSampleRate = 16000.0
  private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
  private var isRunning = false

  // MCSession .unreliable sends are datagram-like: packets larger than the
  // link MTU (~1400 bytes on peer-to-peer wifi) are silently dropped. macOS
  // ignores the requested tap buffer size and delivers 100ms buffers (1600
  // samples = 3200 bytes at 16kHz), so outgoing audio must be chunked to fit.
  private let maxSamplesPerPacket = 640  // 40ms, 1280 bytes

  var onOutgoingAudio: (@Sendable (Data) -> Void)?
  var isMuted = false

  func start() throws {
    guard !isRunning else { return }
    engine.attach(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)
    let inputFormat = engine.inputNode.outputFormat(forBus: 0)
    log("audio engine input format", inputFormat.sampleRate, inputFormat.channelCount)
    warnIfMacInputMuted()
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
      engine.detach(playerNode)
      throw error
    }
    playerNode.play()
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
    guard let floatChannel = buffer.floatChannelData, buffer.frameLength > 0 else { return }

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
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      let samples = raw.bindMemory(to: Int16.self)
      for i in 0..<Int(frameCount) {
        floatChannel.pointee[i] = Float(samples[i]) / Float(Int16.max)
      }
    }
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

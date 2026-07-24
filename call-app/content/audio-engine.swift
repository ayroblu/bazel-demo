import AVFoundation
import Log

nonisolated final class CallAudioEngine: @unchecked Sendable {
  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private let transportFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
  private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
  private var sendConverter: AVAudioConverter?
  private var isRunning = false

  var onOutgoingAudio: (@Sendable (Data) -> Void)?
  var isMuted = false

  func start() throws {
    guard !isRunning else { return }
    try? engine.inputNode.setVoiceProcessingEnabled(true)
    engine.attach(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)
    let inputFormat = engine.inputNode.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0 else {
      throw CallAudioError.noInput
    }
    sendConverter = AVAudioConverter(from: inputFormat, to: transportFormat)
    engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) {
      [weak self] buffer, _ in
      self?.handleMicBuffer(buffer)
    }
    engine.prepare()
    try engine.start()
    playerNode.play()
    isRunning = true
  }

  func stop() {
    guard isRunning else { return }
    playerNode.stop()
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    engine.detach(playerNode)
    sendConverter = nil
    isRunning = false
  }

  private func handleMicBuffer(_ buffer: AVAudioPCMBuffer) {
    guard !isMuted, let converter = sendConverter, let onOutgoingAudio else { return }
    let ratio = transportFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
    guard let outBuffer = AVAudioPCMBuffer(pcmFormat: transportFormat, frameCapacity: capacity)
    else { return }
    var consumed = false
    var error: NSError?
    converter.convert(to: outBuffer, error: &error) { _, outStatus in
      if consumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return buffer
    }
    guard error == nil, outBuffer.frameLength > 0, let channel = outBuffer.int16ChannelData
    else { return }
    let data = Data(
      bytes: channel.pointee, count: Int(outBuffer.frameLength) * MemoryLayout<Int16>.size)
    onOutgoingAudio(data)
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

extension AVAudioApplication {
  static func hasPermissionToRecord() async -> Bool {
    await withCheckedContinuation { continuation in
      AVAudioApplication.requestRecordPermission { authorized in
        continuation.resume(returning: authorized)
      }
    }
  }
}

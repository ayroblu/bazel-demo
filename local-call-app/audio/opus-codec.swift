import AVFoundation

/// Opus over the system codec: 20ms frames of 16kHz mono, ~60-90 bytes each
/// against 640 raw. One encoder and one decoder live for a whole call; both
/// are stateful across frames, so neither can be shared between streams.
public nonisolated enum OpusCall {
  public static let sampleRate = 16000.0
  public static let frameSamples = 320
  public static let frameSeconds = Double(frameSamples) / sampleRate

  static func opusFormat() -> AVAudioFormat? {
    var description = AudioStreamBasicDescription(
      mSampleRate: sampleRate,
      mFormatID: kAudioFormatOpus,
      mFormatFlags: 0,
      mBytesPerPacket: 0,
      mFramesPerPacket: UInt32(frameSamples),
      mBytesPerFrame: 0,
      mChannelsPerFrame: 1,
      mBitsPerChannel: 0,
      mReserved: 0)
    return AVAudioFormat(streamDescription: &description)
  }

  static func pcmFormat() -> AVAudioFormat? {
    AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
  }
}

public nonisolated final class OpusEncoder: @unchecked Sendable {
  private let converter: AVAudioConverter
  private let pcmFormat: AVAudioFormat
  private let opusFormat: AVAudioFormat
  private let lock = NSLock()

  public init?() {
    guard let pcm = OpusCall.pcmFormat(), let opus = OpusCall.opusFormat(),
      let converter = AVAudioConverter(from: pcm, to: opus)
    else { return nil }
    converter.bitRate = 24000
    self.converter = converter
    pcmFormat = pcm
    opusFormat = opus
  }

  public func encode(_ samples: [Float]) -> Data? {
    guard samples.count == OpusCall.frameSamples,
      let input = AVAudioPCMBuffer(
        pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(samples.count))
    else { return nil }
    input.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { source in
      input.floatChannelData!.pointee.update(from: source.baseAddress!, count: samples.count)
    }
    lock.lock()
    defer { lock.unlock() }
    let packet = AVAudioCompressedBuffer(
      format: opusFormat, packetCapacity: 1, maximumPacketSize: 1500)
    let feed = FeedOnce(input)
    var error: NSError?
    let status = converter.convert(to: packet, error: &error) { _, outStatus in
      guard let buffer = feed.take() else {
        outStatus.pointee = .noDataNow
        return nil
      }
      outStatus.pointee = .haveData
      return buffer
    }
    guard status != .error, error == nil, packet.byteLength > 0 else { return nil }
    return Data(bytes: packet.data, count: Int(packet.byteLength))
  }
}

public nonisolated final class OpusDecoder: @unchecked Sendable {
  private let converter: AVAudioConverter
  private let pcmFormat: AVAudioFormat
  private let opusFormat: AVAudioFormat
  private let lock = NSLock()

  public init?() {
    guard let pcm = OpusCall.pcmFormat(), let opus = OpusCall.opusFormat(),
      let converter = AVAudioConverter(from: opus, to: pcm)
    else { return nil }
    self.converter = converter
    pcmFormat = pcm
    opusFormat = opus
  }

  public func decode(_ payload: Data) -> [Float]? {
    guard !payload.isEmpty, payload.count <= 1500 else { return nil }
    lock.lock()
    defer { lock.unlock() }
    let packet = AVAudioCompressedBuffer(
      format: opusFormat, packetCapacity: 1, maximumPacketSize: payload.count)
    payload.withUnsafeBytes { raw in
      packet.data.copyMemory(from: raw.baseAddress!, byteCount: raw.count)
    }
    packet.byteLength = UInt32(payload.count)
    packet.packetCount = 1
    packet.packetDescriptions?[0] = AudioStreamPacketDescription(
      mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(payload.count))
    guard
      let output = AVAudioPCMBuffer(
        pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(OpusCall.frameSamples * 2))
    else { return nil }
    let feed = FeedOnce(packet)
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, outStatus in
      guard let buffer = feed.take() else {
        outStatus.pointee = .noDataNow
        return nil
      }
      outStatus.pointee = .haveData
      return buffer
    }
    guard status != .error, error == nil, output.frameLength > 0 else { return nil }
    return Array(
      UnsafeBufferPointer(
        start: output.floatChannelData!.pointee, count: Int(output.frameLength)))
  }
}

/// Hands the converter its one input buffer, then reports the input dry.
private nonisolated final class FeedOnce: @unchecked Sendable {
  private let lock = NSLock()
  private var buffer: AVAudioBuffer?

  init(_ buffer: AVAudioBuffer) {
    self.buffer = buffer
  }

  func take() -> AVAudioBuffer? {
    lock.lock()
    defer { lock.unlock() }
    let taken = buffer
    buffer = nil
    return taken
  }
}

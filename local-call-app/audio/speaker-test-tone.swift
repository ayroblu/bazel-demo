import AVFoundation

public nonisolated enum SpeakerTestTone {
  public static let packetFrames = OpusCall.frameSamples
  public static let packetSeconds = OpusCall.frameSeconds
  public static let cycleSeconds = 1.5
  public static let chimeSeconds = 0.4

  public static func packets() -> [Data] {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: OpusCall.sampleRate, channels: 1),
      let chime = makeChimeBuffer(format: format),
      let channel = chime.floatChannelData?.pointee,
      let encoder = OpusEncoder()
    else { return [] }
    let chimeFrames = Int(chime.frameLength)
    let totalFrames = max(Int(cycleSeconds * OpusCall.sampleRate), chimeFrames)
    var samples = [Float](repeating: 0, count: totalFrames)
    for index in 0..<chimeFrames {
      samples[index] = max(-1, min(1, channel[index]))
    }
    return stride(from: 0, to: totalFrames - packetFrames + 1, by: packetFrames).compactMap {
      encoder.encode(Array(samples[$0..<($0 + packetFrames)]))
    }
  }
}

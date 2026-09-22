import AVFoundation

/// The disconnect chime and a gap after it, encoded as the frames a peer
/// sends: 16kHz mono Int16 PCM. A speaker test feeds these to the call's own
/// playback queue rather than playing through a path of its own.
public nonisolated enum SpeakerTestTone {
  /// 320 frames, the 20ms packet a call receives.
  public static let packetFrames = 320
  public static let packetSeconds = Double(packetFrames) / 16000
  private static let cycleSeconds = 1.5

  public static func packets() -> [Data] {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
      let chime = makeChimeBuffer(format: format),
      let channel = chime.floatChannelData?.pointee
    else { return [] }
    let chimeFrames = Int(chime.frameLength)
    let totalFrames = max(Int(cycleSeconds * 16000), chimeFrames)
    var samples = [Int16](repeating: 0, count: totalFrames)
    for index in 0..<chimeFrames {
      samples[index] = Int16(max(-1, min(1, channel[index])) * Float(Int16.max))
    }
    return stride(from: 0, to: totalFrames, by: packetFrames).map { start in
      let end = min(start + packetFrames, totalFrames)
      return samples[start..<end].withUnsafeBufferPointer { Data(buffer: $0) }
    }
  }
}

import AVFoundation

/// A descending two tone chime, synthesised rather than shipped as an asset
/// so it follows whatever format the call is already playing at. Each tone
/// fades in and out, otherwise the abrupt edges click.
nonisolated func makeChimeBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
  let tones: [(frequency: Double, seconds: Double)] = [(784, 0.14), (587, 0.26)]
  let sampleRate = format.sampleRate
  guard sampleRate > 0 else { return nil }
  let frameCounts = tones.map { Int($0.seconds * sampleRate) }
  let totalFrames = frameCounts.reduce(0, +)
  guard totalFrames > 0,
    let buffer = AVAudioPCMBuffer(
      pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)),
    let channels = buffer.floatChannelData
  else { return nil }
  buffer.frameLength = AVAudioFrameCount(totalFrames)

  let peak = 0.3
  let attackFrames = max(1.0, 0.005 * sampleRate)
  var index = 0
  for (tone, frames) in zip(tones, frameCounts) {
    for offset in 0..<frames {
      let attack = min(1, Double(offset) / attackFrames)
      let release = pow(1 - Double(offset) / Double(frames), 2)
      let phase = 2 * Double.pi * tone.frequency * Double(offset) / sampleRate
      let sample = Float(sin(phase) * attack * release * peak)
      for channel in 0..<Int(format.channelCount) {
        channels[channel][index] = sample
      }
      index += 1
    }
  }
  return buffer
}

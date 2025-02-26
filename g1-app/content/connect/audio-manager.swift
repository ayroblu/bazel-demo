import AVFoundation
import Log

class AudioManager {
  let outputUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("output.aac")
  var audioFile: AVAudioFile?
  var audioPlayer: AVAudioPlayer?

  func open() {
    try? FileManager.default.removeItem(at: outputUrl)
    audioFile = try? AVAudioFile(
      forWriting: outputUrl,
      settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
      ],
      commonFormat: .pcmFormatInt16, interleaved: false)
  }

  func write(audioBuffer: AVAudioPCMBuffer) {
    try? audioFile?.write(from: audioBuffer)
  }

  func close() {
    audioFile?.close()
    audioFile = nil
  }

  func listen() {
    audioPlayer = try? AVAudioPlayer(contentsOf: outputUrl)
    if let audioPlayer {
      log("audioplayer play")
      audioPlayer.play()
    } else {
      log("no audioplayer")
    }
  }
}

import AVFoundation
import XCTest

@testable import audio

final class SpeakerTestToneTests: XCTestCase {
  private func decodeAll(_ packets: [Data]) -> [Float] {
    let decoder = OpusDecoder()!
    return packets.flatMap { decoder.decode($0) ?? [] }
  }

  func testPacketsCoverOneCycle() {
    let packets = SpeakerTestTone.packets()
    XCTAssertFalse(packets.isEmpty)
    for packet in packets {
      XCTAssertGreaterThan(packet.count, 0)
      XCTAssertLessThan(packet.count, 200)
    }
    let frames = packets.count * SpeakerTestTone.packetFrames
    XCTAssertEqual(Double(frames) / OpusCall.sampleRate, 1.5, accuracy: 0.02)
    XCTAssertEqual(SpeakerTestTone.packetSeconds, 0.02, accuracy: 0.0001)
  }

  func testChimePlaysThenGoesQuiet() {
    let all = decodeAll(SpeakerTestTone.packets())
    let chimeFrames = Int(SpeakerTestTone.chimeSeconds * OpusCall.sampleRate)
    XCTAssertGreaterThan(all.count, chimeFrames)

    let chimePeak = all[..<min(chimeFrames, all.count)].map { abs($0) }.max() ?? 0
    XCTAssertGreaterThan(chimePeak, 0.05)
    // The rest of the cycle is encoded silence; the codec's ring-down after
    // the chime must die out fast and the tail must stay inaudible.
    let tailStart = chimeFrames + Int(0.05 * OpusCall.sampleRate)
    let tailPeak = all[tailStart...].map { abs($0) }.max() ?? 0
    XCTAssertLessThan(tailPeak, 0.01)
  }

  func testChimeToneSurvivesTheCodec() {
    let all = decodeAll(SpeakerTestTone.packets())
    // The first chime tone is 784Hz for 0.14s; count zero crossings over its
    // settled middle to confirm the codec kept the pitch.
    let from = Int(0.03 * OpusCall.sampleRate)
    let to = Int(0.12 * OpusCall.sampleRate)
    var crossings = 0
    for index in (from + 1)..<to where all[index - 1] < 0 && all[index] >= 0 {
      crossings += 1
    }
    let frequency = Double(crossings) * OpusCall.sampleRate / Double(to - from)
    XCTAssertEqual(frequency, 784, accuracy: 30)
  }
}

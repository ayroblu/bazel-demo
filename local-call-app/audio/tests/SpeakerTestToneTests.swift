import AVFoundation
import XCTest

@testable import audio

final class SpeakerTestToneTests: XCTestCase {
  private func samples(_ packet: Data) -> [Int16] {
    packet.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
  }

  func testPacketsCoverOneCycle() {
    let packets = SpeakerTestTone.packets()
    XCTAssertFalse(packets.isEmpty)
    for packet in packets {
      XCTAssertEqual(packet.count, SpeakerTestTone.packetFrames * MemoryLayout<Int16>.size)
    }
    let frames = packets.count * SpeakerTestTone.packetFrames
    XCTAssertEqual(Double(frames) / 16000, 1.5, accuracy: 0.02)
    XCTAssertEqual(SpeakerTestTone.packetSeconds, 0.02, accuracy: 0.0001)
  }

  func testChimePlaysThenGoesQuiet() {
    let packets = SpeakerTestTone.packets()
    let all = packets.flatMap(samples)
    let chimeFrames = Int(0.4 * 16000)

    let chimePeak = all[0..<chimeFrames].map { abs(Int32($0)) }.max() ?? 0
    XCTAssertGreaterThan(chimePeak, Int32(Int16.max) / 10)
    XCTAssertTrue(all[chimeFrames...].allSatisfy { $0 == 0 })
  }

  func testSamplesMatchTheChime() {
    let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    guard let chime = makeChimeBuffer(format: format),
      let channel = chime.floatChannelData?.pointee
    else { return XCTFail("no chime buffer") }
    let all = SpeakerTestTone.packets().flatMap(samples)

    for index in stride(from: 0, to: Int(chime.frameLength), by: 97) {
      XCTAssertEqual(
        Float(all[index]) / Float(Int16.max), channel[index], accuracy: 0.001,
        "frame \(index)")
    }
  }
}

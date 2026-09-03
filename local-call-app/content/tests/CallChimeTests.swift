import AVFoundation
import XCTest

@testable import content

final class CallChimeTests: XCTestCase {
  func testChimeBuffer() {
    let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    let buffer = makeChimeBuffer(format: format)
    XCTAssertNotNil(buffer)
    guard let buffer, let channel = buffer.floatChannelData?.pointee else { return }

    XCTAssertEqual(buffer.frameLength, AVAudioFrameCount(0.4 * 16000))

    let samples = (0..<Int(buffer.frameLength)).map { channel[$0] }
    let peak = samples.map { abs($0) }.max() ?? 0
    XCTAssertGreaterThan(peak, 0.1)
    XCTAssertLessThanOrEqual(peak, 0.3)

    // Both tones fade in and out, so the edges and the seam between them must
    // be silent or the chime clicks.
    XCTAssertEqual(samples[0], 0, accuracy: 0.001)
    XCTAssertEqual(samples[samples.count - 1], 0, accuracy: 0.001)
    let seam = Int(0.14 * 16000)
    XCTAssertEqual(samples[seam - 1], 0, accuracy: 0.01)
    XCTAssertEqual(samples[seam], 0, accuracy: 0.01)
  }

  func testChimeTonesDescend() {
    let sampleRate = 16000.0
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    guard let buffer = makeChimeBuffer(format: format),
      let channel = buffer.floatChannelData?.pointee
    else { return XCTFail("no chime buffer") }

    func frequency(from: Int, to: Int) -> Double {
      var crossings = 0
      for index in (from + 1)..<to where channel[index - 1] < 0 && channel[index] >= 0 {
        crossings += 1
      }
      return Double(crossings) * sampleRate / Double(to - from)
    }

    XCTAssertEqual(frequency(from: 160, to: 2000), 784, accuracy: 20)
    XCTAssertEqual(frequency(from: 2400, to: 5600), 587, accuracy: 20)
  }

  func testChimeFillsEveryChannel() {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    guard let buffer = makeChimeBuffer(format: format), let channels = buffer.floatChannelData
    else { return XCTFail("no chime buffer") }

    XCTAssertEqual(buffer.format.channelCount, 2)
    let mid = Int(buffer.frameLength) / 2
    XCTAssertEqual(channels[0][mid], channels[1][mid])
    XCTAssertNotEqual(channels[0][mid], 0)
  }
}

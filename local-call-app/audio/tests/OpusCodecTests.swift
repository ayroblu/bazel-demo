import AVFoundation
import XCTest

@testable import audio

final class OpusCodecTests: XCTestCase {
  private func sineFrame(index: Int, frequency: Float = 440) -> [Float] {
    let start = index * OpusCall.frameSamples
    return (0..<OpusCall.frameSamples).map { offset in
      sinf(Float(start + offset) * 2 * .pi * frequency / Float(OpusCall.sampleRate)) * 0.5
    }
  }

  func testEncodesEveryFrameWellUnderPcmSize() throws {
    let encoder = try XCTUnwrap(OpusEncoder())
    for index in 0..<50 {
      let packet = try XCTUnwrap(encoder.encode(sineFrame(index: index)))
      XCTAssertGreaterThan(packet.count, 0)
      XCTAssertLessThan(packet.count, 200, "frame \(index) larger than expected")
    }
  }

  func testRoundTripPreservesToneAndDuration() throws {
    let encoder = try XCTUnwrap(OpusEncoder())
    let decoder = try XCTUnwrap(OpusDecoder())
    let frameCount = 50
    var decoded: [Float] = []
    for index in 0..<frameCount {
      let packet = try XCTUnwrap(encoder.encode(sineFrame(index: index)))
      decoded.append(contentsOf: try XCTUnwrap(decoder.decode(packet)))
    }
    // The decoder's priming skip may eat a few ms at the start, never more.
    let expected = frameCount * OpusCall.frameSamples
    XCTAssertGreaterThan(decoded.count, expected - OpusCall.frameSamples)
    XCTAssertLessThanOrEqual(decoded.count, expected)

    // Codec delay means the start is quiet, so judge the settled second half.
    let half = Array(decoded[(decoded.count / 2)...])
    let peak = half.map { abs($0) }.max() ?? 0
    XCTAssertEqual(peak, 0.5, accuracy: 0.15)
    var crossings = 0
    for index in 1..<half.count where half[index - 1] < 0 && half[index] >= 0 {
      crossings += 1
    }
    let frequency = Double(crossings) * OpusCall.sampleRate / Double(half.count)
    XCTAssertEqual(frequency, 440, accuracy: 15)
  }

  func testRejectsWrongSizeInput() throws {
    let encoder = try XCTUnwrap(OpusEncoder())
    XCTAssertNil(encoder.encode([Float](repeating: 0, count: 100)))
    let decoder = try XCTUnwrap(OpusDecoder())
    XCTAssertNil(decoder.decode(Data()))
  }
}

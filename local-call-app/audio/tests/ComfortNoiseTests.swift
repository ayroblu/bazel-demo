import XCTest

@testable import audio

final class ComfortNoiseTests: XCTestCase {
  func testFramesAreQuietButNotSilent() {
    for _ in 0..<10 {
      let frame = ComfortNoise.frame(samples: OpusCall.frameSamples)
      XCTAssertEqual(frame.count, OpusCall.frameSamples)
      let peak = frame.map { abs($0) }.max() ?? 0
      XCTAssertLessThanOrEqual(peak, ComfortNoise.amplitude)
      XCTAssertGreaterThan(peak, 0)
      // White noise is zero-mean; a bias would pop when it starts and stops.
      let mean = frame.reduce(0, +) / Float(frame.count)
      XCTAssertEqual(mean, 0, accuracy: 0.005)
    }
  }

  func testAmplitudeIsWellBelowSpeech() {
    XCTAssertLessThan(ComfortNoise.amplitude, 0.05)
  }
}

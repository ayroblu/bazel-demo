import Foundation
import XCTest

@testable import audio

final class JitterBufferTests: XCTestCase {
  func testInOrderFramesPlayWithNoFill() {
    let jitter = JitterBuffer()
    for seq in UInt32(0)..<50 {
      XCTAssertEqual(jitter.push(seq: seq), JitterBuffer.Placement(fillFrames: 0, play: true))
    }
    let stats = jitter.stats()
    XCTAssertEqual(stats.lost, 0)
    XCTAssertEqual(stats.late, 0)
    XCTAssertEqual(stats.discontinuities, 0)
  }

  func testFirstSeqIsTheBaseline() {
    let jitter = JitterBuffer()
    XCTAssertEqual(jitter.push(seq: 900), JitterBuffer.Placement(fillFrames: 0, play: true))
    XCTAssertEqual(jitter.push(seq: 901), JitterBuffer.Placement(fillFrames: 0, play: true))
  }

  func testShortGapIsFilledWithSilence() {
    let jitter = JitterBuffer()
    _ = jitter.push(seq: 0)
    XCTAssertEqual(jitter.push(seq: 4), JitterBuffer.Placement(fillFrames: 3, play: true))
    XCTAssertEqual(jitter.stats().lost, 3)
    XCTAssertEqual(jitter.push(seq: 5), JitterBuffer.Placement(fillFrames: 0, play: true))
  }

  func testLongGapSkipsWithoutFill() {
    let jitter = JitterBuffer(maxFillFrames: 15)
    _ = jitter.push(seq: 0)
    XCTAssertEqual(jitter.push(seq: 100), JitterBuffer.Placement(fillFrames: 0, play: true))
    XCTAssertEqual(jitter.stats().discontinuities, 1)
    XCTAssertEqual(jitter.push(seq: 101), JitterBuffer.Placement(fillFrames: 0, play: true))
  }

  func testLateAndDuplicateFramesAreDropped() {
    let jitter = JitterBuffer()
    _ = jitter.push(seq: 0)
    _ = jitter.push(seq: 1)
    XCTAssertEqual(jitter.push(seq: 1), JitterBuffer.Placement(fillFrames: 0, play: false))
    XCTAssertEqual(jitter.push(seq: 0), JitterBuffer.Placement(fillFrames: 0, play: false))
    XCTAssertEqual(jitter.stats().late, 2)
    XCTAssertEqual(jitter.push(seq: 2), JitterBuffer.Placement(fillFrames: 0, play: true))
  }

  func testResetTakesTheNextSeqAsNewBaseline() {
    let jitter = JitterBuffer()
    _ = jitter.push(seq: 0)
    jitter.reset()
    XCTAssertEqual(jitter.push(seq: 5000), JitterBuffer.Placement(fillFrames: 0, play: true))
    XCTAssertEqual(jitter.stats().lost, 0)
  }
}

final class CatchUpControllerTests: XCTestCase {
  private func at(_ seconds: Double) -> Date {
    Date(timeIntervalSinceReferenceDate: seconds)
  }

  func testSmallBacklogPlaysAtNormalRate() {
    let control = CatchUpController()
    for tick in 0..<300 {
      let rate = control.record(backlogFrames: 320 + (tick % 3) * 320, at: at(Double(tick) * 0.02))
      XCTAssertEqual(rate, 1)
    }
  }

  func testJitterPeaksAboveASmallFloorAreLeftAlone() {
    let control = CatchUpController()
    var maxRate: Float = 1
    // Bursty queue swinging 0..2400 frames: the minimum stays under target,
    // so none of it is standing delay worth chasing.
    for tick in 0..<300 {
      let backlog = tick % 5 == 0 ? 0 : 2400
      maxRate = max(maxRate, control.record(backlogFrames: backlog, at: at(Double(tick) * 0.02)))
    }
    XCTAssertEqual(maxRate, 1)
  }

  func testStandingBacklogRaisesRateUpToTheCap() {
    let control = CatchUpController()
    var rate: Float = 1
    for tick in 0..<300 {
      rate = control.record(backlogFrames: 8000, at: at(Double(tick) * 0.02))
    }
    XCTAssertEqual(rate, 1.08, accuracy: 0.001)
  }

  func testRateScalesWithStandingBacklog() {
    let control = CatchUpController()
    var rate: Float = 1
    for tick in 0..<300 {
      rate = control.record(backlogFrames: 960 + 2400, at: at(Double(tick) * 0.02))
    }
    XCTAssertGreaterThan(rate, 1.02)
    XCTAssertLessThan(rate, 1.06)
  }

  func testResetForgetsTheBacklogHistory() {
    let control = CatchUpController()
    for tick in 0..<300 {
      _ = control.record(backlogFrames: 8000, at: at(Double(tick) * 0.02))
    }
    control.reset()
    XCTAssertEqual(control.record(backlogFrames: 0, at: at(6.02)), 1)
  }
}

import Foundation

/// Orders a call's incoming frames by sequence number. A short gap is filled
/// with silence so lost packets cost their own 20ms and nothing more; a long
/// gap is a stall that playback has already absorbed as silence, so it is
/// noted and skipped rather than replayed. Late and duplicate frames are
/// dropped: their moment has passed.
public nonisolated final class JitterBuffer: @unchecked Sendable {
  public struct Placement: Equatable {
    public let fillFrames: Int
    public let play: Bool
  }

  private let lock = NSLock()
  private var expectedSeq: UInt32?
  private var lostFrames = 0
  private var lateFrames = 0
  private var discontinuities = 0
  private let maxFillFrames: Int

  public init(maxFillFrames: Int = 15) {
    self.maxFillFrames = maxFillFrames
  }

  public func push(seq: UInt32) -> Placement {
    lock.lock()
    defer { lock.unlock() }
    guard let expected = expectedSeq else {
      expectedSeq = seq &+ 1
      return Placement(fillFrames: 0, play: true)
    }
    if seq == expected {
      expectedSeq = seq &+ 1
      return Placement(fillFrames: 0, play: true)
    }
    let gap = Int(Int64(seq) - Int64(expected))
    if gap > 0 {
      expectedSeq = seq &+ 1
      if gap <= maxFillFrames {
        lostFrames += gap
        return Placement(fillFrames: gap, play: true)
      }
      lostFrames += gap
      discontinuities += 1
      return Placement(fillFrames: 0, play: true)
    }
    lateFrames += 1
    return Placement(fillFrames: 0, play: false)
  }

  public func stats() -> (lost: Int, late: Int, discontinuities: Int) {
    lock.lock()
    defer { lock.unlock() }
    return (lostFrames, lateFrames, discontinuities)
  }

  public func reset() {
    lock.lock()
    expectedSeq = nil
    lock.unlock()
  }
}

/// Decides how fast playback should run, WebRTC-style: the queue is sampled
/// on every arrival and only its *minimum* over a sliding window is ever
/// removed. The minimum is standing delay that jitter never eats into, so
/// draining it cannot starve the player; the peaks above it are the jitter
/// margin and are left alone. Below the target the rate is 1: the last word
/// of latency is cheaper than chasing it audibly forever.
public nonisolated final class CatchUpController: @unchecked Sendable {
  private let lock = NSLock()
  private var samples: [(at: Date, backlogFrames: Int)] = []

  private let targetFrames: Int
  private let spanFrames: Int
  private let maxRate: Float
  private let window: TimeInterval

  public init(
    targetFrames: Int = 960,  // 60ms at 16kHz
    spanFrames: Int = 4800,  // rate tops out 300ms past the target
    maxRate: Float = 1.08,
    window: TimeInterval = 3
  ) {
    self.targetFrames = targetFrames
    self.spanFrames = spanFrames
    self.maxRate = maxRate
    self.window = window
  }

  public func record(backlogFrames: Int, at now: Date = Date()) -> Float {
    lock.lock()
    defer { lock.unlock() }
    samples.append((now, backlogFrames))
    while let first = samples.first, now.timeIntervalSince(first.at) > window {
      samples.removeFirst()
    }
    let standing = samples.map { $0.backlogFrames }.min() ?? 0
    let excess = Float(standing - targetFrames)
    guard excess > 0 else { return 1 }
    return 1 + min(maxRate - 1, (excess / Float(spanFrames)) * (maxRate - 1))
  }

  public func reset() {
    lock.lock()
    samples = []
    lock.unlock()
  }
}

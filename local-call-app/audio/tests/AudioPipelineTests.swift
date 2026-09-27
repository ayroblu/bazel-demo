import Foundation
import XCTest

@testable import audio

/// The receiving half of a call with the transport mocked out: opus packets
/// are pushed in on a simulated arrival clock and playback consumption is
/// simulated the way the engine's player behaves, so arrival patterns (jitter,
/// bursts, loss, stalls) can be checked for smooth output without hardware.
private final class ReceiverSim {
  let decoder = OpusDecoder()!
  let jitter = JitterBuffer()
  let catchUp = CatchUpController()

  private(set) var playedSamples = 0
  private(set) var silenceSamples = 0
  private(set) var droppedPackets = 0
  private(set) var maxRate: Float = 1
  private(set) var rate: Float = 1
  private var scheduledSamples = 0
  private var consumedSamples = 0.0
  private var lastTime: Double?

  var backlogFrames: Int { max(0, scheduledSamples - Int(consumedSamples)) }

  func deliver(seq: UInt32, packet: Data, at time: Double) {
    advance(to: time)
    guard let samples = decoder.decode(packet) else {
      XCTFail("packet \(seq) failed to decode")
      return
    }
    let placement = jitter.push(seq: seq)
    if placement.fillFrames > 0 {
      let fill = placement.fillFrames * OpusCall.frameSamples
      silenceSamples += fill
      scheduledSamples += fill
    }
    if placement.play {
      playedSamples += samples.count
      scheduledSamples += samples.count
    } else {
      droppedPackets += 1
    }
    rate = catchUp.record(
      backlogFrames: backlogFrames, at: Date(timeIntervalSinceReferenceDate: time))
    maxRate = max(maxRate, rate)
  }

  /// The player consumes queued samples at the catch up rate and pauses when
  /// the queue is empty, which is how a starved AVAudioPlayerNode behaves.
  func advance(to time: Double) {
    if let lastTime {
      let renderable = (time - lastTime) * OpusCall.sampleRate * Double(rate)
      consumedSamples = min(Double(scheduledSamples), consumedSamples + renderable)
    }
    lastTime = time
  }
}

final class AudioPipelineTests: XCTestCase {
  private func packets(count: Int) -> [Data] {
    let encoder = OpusEncoder()!
    return (0..<count).map { index in
      let start = index * OpusCall.frameSamples
      let frame = (0..<OpusCall.frameSamples).map { offset in
        sinf(Float(start + offset) * 2 * .pi * 300 / Float(OpusCall.sampleRate)) * 0.4
      }
      return encoder.encode(frame)!
    }
  }

  func testSteadyArrivalPlaysEverythingAtNormalRate() {
    let sim = ReceiverSim()
    let packets = packets(count: 250)
    for (index, packet) in packets.enumerated() {
      sim.deliver(seq: UInt32(index), packet: packet, at: Double(index) * 0.02)
    }
    XCTAssertEqual(sim.silenceSamples, 0)
    XCTAssertEqual(sim.droppedPackets, 0)
    XCTAssertEqual(sim.maxRate, 1)
    XCTAssertGreaterThan(sim.playedSamples, (packets.count - 1) * OpusCall.frameSamples)
  }

  func testBurstyArrivalStaysSmoothWithoutCatchUp() {
    let sim = ReceiverSim()
    let packets = packets(count: 300)
    // Five packets land at once every 100ms: jitter the buffer should ride
    // out with no silence gaps and no rate change.
    for (index, packet) in packets.enumerated() {
      let burstTime = Double(index / 5) * 0.1
      sim.deliver(seq: UInt32(index), packet: packet, at: burstTime)
    }
    XCTAssertEqual(sim.silenceSamples, 0)
    XCTAssertEqual(sim.droppedPackets, 0)
    XCTAssertEqual(sim.maxRate, 1)
  }

  func testLostPacketsCostExactlyTheirOwnSilence() {
    let sim = ReceiverSim()
    let packets = packets(count: 200)
    let lost: Set<Int> = [40, 41, 90]
    for (index, packet) in packets.enumerated() where !lost.contains(index) {
      sim.deliver(seq: UInt32(index), packet: packet, at: Double(index) * 0.02)
    }
    XCTAssertEqual(sim.silenceSamples, lost.count * OpusCall.frameSamples)
    XCTAssertEqual(sim.droppedPackets, 0)
    XCTAssertEqual(sim.jitter.stats().lost, lost.count)
    XCTAssertEqual(sim.maxRate, 1)
  }

  func testReorderedAndDuplicatedPacketsDoNotCorruptTheStream() {
    let sim = ReceiverSim()
    let packets = packets(count: 8)
    let arrivals: [(Int, Double)] = [
      (0, 0), (1, 0.02), (3, 0.06), (2, 0.07), (4, 0.08), (4, 0.081), (5, 0.1), (6, 0.12),
      (7, 0.14),
    ]
    for (index, time) in arrivals {
      sim.deliver(seq: UInt32(index), packet: packets[index], at: time)
    }
    // Seq 3 arrives before 2, so 2 is a frame of silence and the late real 2
    // and the duplicate 4 are dropped; everything else plays once, in order.
    XCTAssertEqual(sim.silenceSamples, OpusCall.frameSamples)
    XCTAssertEqual(sim.droppedPackets, 2)
    XCTAssertEqual(sim.jitter.stats().late, 2)
  }

  func testStallThenBurstCatchesUpAndSettles() {
    let sim = ReceiverSim()
    let packets = packets(count: 1500)
    var maxBacklogAfterRecovery = Int.max
    for (index, packet) in packets.enumerated() {
      let sent = Double(index) * 0.02
      // 2s flows normally, then a 700ms stall: packets sent during it all
      // arrive with the burst when the network recovers, and everything after
      // flows normally again but a stall's worth late.
      let arrival = sent < 2.0 ? sent : max(sent, 2.7)
      sim.deliver(seq: UInt32(index), packet: packet, at: arrival)
      if sent > 25 {
        maxBacklogAfterRecovery = min(maxBacklogAfterRecovery, sim.backlogFrames)
      }
    }
    XCTAssertEqual(sim.silenceSamples, 0)
    XCTAssertEqual(sim.droppedPackets, 0)
    // The stall parked ~700ms of standing delay; catch up must engage...
    XCTAssertGreaterThan(sim.maxRate, 1.05)
    // ...and drain it back under ~150ms, with the rate easing off to hover
    // at the target.
    XCTAssertLessThan(maxBacklogAfterRecovery, 2400)
    XCTAssertEqual(sim.rate, 1, accuracy: 0.01)
  }

  func testClockDriftIsAbsorbedInsteadOfAccumulating() {
    let sim = ReceiverSim()
    let packets = packets(count: 2000)
    // The peer's clock runs 1% fast: 20ms of audio arrives every 19.8ms, a
    // realistic drift that would otherwise grow the queue by 600ms a minute.
    for (index, packet) in packets.enumerated() {
      sim.deliver(seq: UInt32(index), packet: packet, at: Double(index) * 0.0198)
    }
    XCTAssertLessThan(sim.backlogFrames, 2400)
    XCTAssertGreaterThan(sim.maxRate, 1)
    XCTAssertEqual(sim.silenceSamples, 0)
  }
}

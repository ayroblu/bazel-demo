import Foundation
import XCTest

@testable import audio

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
      let arrival = sent < 2.0 ? sent : max(sent, 2.7)
      sim.deliver(seq: UInt32(index), packet: packet, at: arrival)
      if sent > 25 {
        maxBacklogAfterRecovery = min(maxBacklogAfterRecovery, sim.backlogFrames)
      }
    }
    XCTAssertEqual(sim.silenceSamples, 0)
    XCTAssertEqual(sim.droppedPackets, 0)
    XCTAssertGreaterThan(sim.maxRate, 1.05)
    XCTAssertLessThan(maxBacklogAfterRecovery, 2400)
    XCTAssertEqual(sim.rate, 1, accuracy: 0.01)
  }

  func testClockDriftIsAbsorbedInsteadOfAccumulating() {
    let sim = ReceiverSim()
    let packets = packets(count: 2000)
    for (index, packet) in packets.enumerated() {
      sim.deliver(seq: UInt32(index), packet: packet, at: Double(index) * 0.0198)
    }
    XCTAssertLessThan(sim.backlogFrames, 2400)
    XCTAssertGreaterThan(sim.maxRate, 1)
    XCTAssertEqual(sim.silenceSamples, 0)
  }
}

import Foundation
import XCTest

@testable import content

final class AudioStreamTests: XCTestCase {
  private func boundPair(bufferSize: Int) -> (InputStream, OutputStream) {
    var input: InputStream?
    var output: OutputStream?
    Stream.getBoundStreams(
      withBufferSize: bufferSize, inputStream: &input, outputStream: &output)
    return (input!, output!)
  }

  func testAudioStreamDelivery() {
    let (rawInput, rawOutput) = boundPair(bufferSize: 8192)
    let received = Received()
    let gotAll = expectation(description: "received all samples")
    let input = AudioInputStream(stream: rawInput, peerName: "peer") { data in
      if received.append(data) >= 6 {
        gotAll.fulfill()
      }
    }
    let output = AudioOutputStream(stream: rawOutput, peerName: "peer")

    // A trailing odd byte must be held back until its pair arrives, so three
    // bytes then one byte has to arrive as two whole Int16 samples.
    output.send(Data([1, 2, 3]))
    output.send(Data([4]))
    output.send(Data([5, 6]))

    wait(for: [gotAll], timeout: 5)
    XCTAssertEqual(received.bytes(), Data([1, 2, 3, 4, 5, 6]))
    XCTAssertTrue(received.chunks().allSatisfy { $0.count % 2 == 0 })
    XCTAssertEqual(input.stats().received, 6)
    XCTAssertEqual(output.stats().sent, 6)
    output.close()
    input.close()
  }

  func testAudioStreamSustainsContinuousAudio() {
    // A call writes 3200 bytes every 100ms for its whole life, so reading has
    // to keep up indefinitely, not just for the first buffer.
    let (rawInput, rawOutput) = boundPair(bufferSize: 8192)
    let total = 32000
    let received = Received()
    let gotAll = expectation(description: "received the whole run")
    let input = AudioInputStream(stream: rawInput, peerName: "peer") { data in
      if received.append(data) >= total {
        gotAll.fulfill()
      }
    }
    let output = AudioOutputStream(stream: rawOutput, peerName: "peer")

    let chunk = Data(repeating: 3, count: 1600)
    var writes = 0
    let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
      output.send(chunk)
      writes += 1
      if writes == total / chunk.count {
        timer.invalidate()
      }
    }
    wait(for: [gotAll], timeout: 10)
    timer.invalidate()

    XCTAssertEqual(received.bytes().count, total)
    XCTAssertEqual(input.stats().received, total)
    output.close()
    input.close()
  }

  func testAudioStreamDropsBacklogWhenPeerStops() {
    // Nothing reads the input side, so the writer fills up and the send queue
    // has to shed the oldest audio instead of growing without bound.
    let (rawInput, rawOutput) = boundPair(bufferSize: 64)
    let output = AudioOutputStream(stream: rawOutput, peerName: "peer")

    let chunk = Data(repeating: 7, count: 3200)
    for _ in 0..<20 {
      output.send(chunk)
    }

    let dropped = expectation(description: "dropped stale audio")
    let poll = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
      if output.stats().dropped > 0 {
        timer.invalidate()
        dropped.fulfill()
      }
    }
    wait(for: [dropped], timeout: 5)
    poll.invalidate()

    // 200ms of 16kHz mono Int16 audio is the cap, so almost all of the 64000
    // bytes written must have been dropped rather than queued.
    XCTAssertGreaterThan(output.stats().dropped, 64000 - 6400 - 8192)
    output.close()
    rawInput.close()
  }
}

private final class Received: @unchecked Sendable {
  private let lock = NSLock()
  private var data = Data()
  private var received: [Data] = []

  func append(_ chunk: Data) -> Int {
    lock.lock()
    defer { lock.unlock() }
    data.append(chunk)
    received.append(chunk)
    return data.count
  }

  func bytes() -> Data {
    lock.lock()
    defer { lock.unlock() }
    return data
  }

  func chunks() -> [Data] {
    lock.lock()
    defer { lock.unlock() }
    return received
  }
}

import Foundation
import XCTest

import l2cap

@testable import transport

/// The L2CAP path without bluetooth: crossed pairs of bound Foundation
/// streams stand in for the channel, so framing, sealing and the call
/// protocol on top all run exactly as they do on a real channel.
final class StreamCarrierTests: XCTestCase {
  private let secret = Data(repeating: 7, count: 32)

  private func boundPair() -> (input: InputStream, output: OutputStream) {
    var input: InputStream?
    var output: OutputStream?
    Stream.getBoundStreams(withBufferSize: 64 * 1024, inputStream: &input, outputStream: &output)
    return (input!, output!)
  }

  private func linkedCarriers(
    callerSecret: Data, answererSecret: Data
  ) -> (caller: StreamDatagramCarrier, answerer: StreamDatagramCarrier) {
    let callerToAnswerer = boundPair()
    let answererToCaller = boundPair()
    let caller = StreamDatagramCarrier(
      input: answererToCaller.input, output: callerToAnswerer.output, secret: callerSecret,
      label: "caller")
    let answerer = StreamDatagramCarrier(
      input: callerToAnswerer.input, output: answererToCaller.output, secret: answererSecret,
      label: "answerer")
    return (caller, answerer)
  }

  func testCarriesSequencedAudioBothWays() {
    let carriers = linkedCarriers(callerSecret: secret, answererSecret: secret)
    let caller = PeerConnection(
      carrier: carriers.caller, localIdentity: "caller-id", greetsOnReady: true)
    let answerer = PeerConnection(
      carrier: carriers.answerer, localIdentity: "answerer-id", greetsOnReady: false)

    let callerSaw = expectation(description: "caller saw answerer")
    let answererGot = Received()
    let callerGot = Received()
    let answererGotAll = expectation(description: "answerer got audio")
    let callerGotAll = expectation(description: "caller got audio")
    caller.setHandlers(
      onReady: { identity in
        XCTAssertEqual(identity, "answerer-id")
        callerSaw.fulfill()
      },
      onData: { seq, data in
        if callerGot.append(seq: seq, data: data) == 2 {
          callerGotAll.fulfill()
        }
      }, onClosed: nil)
    answerer.setHandlers(
      onReady: { _ in answerer.greet() },
      onData: { seq, data in
        if answererGot.append(seq: seq, data: data) == 2 {
          answererGotAll.fulfill()
        }
      }, onClosed: nil)

    caller.start()
    answerer.start()
    wait(for: [callerSaw], timeout: 10)

    caller.send(Data([1, 2, 3]))
    caller.send(Data(repeating: 9, count: 200))
    answerer.send(Data([4]))
    answerer.send(Data([5, 6]))
    wait(for: [answererGotAll, callerGotAll], timeout: 10)

    let toAnswerer = Dictionary(answererGot.packets()) { first, _ in first }
    XCTAssertEqual(toAnswerer[0], Data([1, 2, 3]))
    XCTAssertEqual(toAnswerer[1], Data(repeating: 9, count: 200))
    let toCaller = Dictionary(callerGot.packets()) { first, _ in first }
    XCTAssertEqual(toCaller[0], Data([4]))
    XCTAssertEqual(toCaller[1], Data([5, 6]))

    caller.cancel()
    answerer.cancel()
  }

  func testMeasuresRttOverStreams() throws {
    let carriers = linkedCarriers(callerSecret: secret, answererSecret: secret)
    let caller = PeerConnection(
      carrier: carriers.caller, localIdentity: "caller-id", greetsOnReady: true)
    let answerer = PeerConnection(
      carrier: carriers.answerer, localIdentity: "answerer-id", greetsOnReady: false)
    caller.setHandlers(onReady: nil, onData: nil, onClosed: nil)
    answerer.setHandlers(onReady: { _ in answerer.greet() }, onData: nil, onClosed: nil)
    caller.start()
    answerer.start()
    defer {
      caller.cancel()
      answerer.cancel()
    }

    let deadline = Date().addingTimeInterval(10)
    while caller.rttMs() == nil, Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    let rtt = try XCTUnwrap(caller.rttMs())
    XCTAssertGreaterThanOrEqual(rtt, 0)
    XCTAssertLessThan(rtt, 5000)
  }

  /// A peer with a different pairing secret cannot produce datagrams we can
  /// open, and the connection must die rather than carry on around it.
  func testWrongSecretClosesTheLink() {
    let carriers = linkedCarriers(
      callerSecret: secret, answererSecret: Data(repeating: 8, count: 32))
    let caller = PeerConnection(
      carrier: carriers.caller, localIdentity: "caller-id", greetsOnReady: true)
    let answerer = PeerConnection(
      carrier: carriers.answerer, localIdentity: "answerer-id", greetsOnReady: false)
    let closed = expectation(description: "answerer closed")
    caller.setHandlers(onReady: nil, onData: nil, onClosed: nil)
    answerer.setHandlers(
      onReady: { _ in XCTFail("hello should not survive a wrong secret") },
      onData: nil,
      onClosed: { reason in
        XCTAssertTrue(reason.contains("unsealable"), reason)
        closed.fulfill()
      })
    caller.start()
    answerer.start()
    wait(for: [closed], timeout: 10)
    caller.cancel()
    answerer.cancel()
  }
}

private final class Received: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [(UInt32, Data)] = []

  func append(seq: UInt32, data: Data) -> Int {
    lock.lock()
    defer { lock.unlock() }
    stored.append((seq, data))
    return stored.count
  }

  func packets() -> [(UInt32, Data)] {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }
}

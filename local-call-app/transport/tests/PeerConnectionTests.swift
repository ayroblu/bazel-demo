import Foundation
import Network
import XCTest

@testable import transport

final class PeerConnectionTests: XCTestCase {
  /// Two connections over the loopback interface, using the same parameters
  /// as a real call, so the TLS handshake and the hello exchange are covered
  /// along with the audio.
  private func connectedPair(
    onDialledData: @escaping @Sendable (Data) -> Void,
    onAnsweredData: @escaping @Sendable (Data) -> Void
  ) throws -> (dialled: PeerConnection, answered: PeerConnection, listener: NWListener) {
    let listener = try NWListener(using: PeerConnection.parameters())
    let answered = Holder<PeerConnection>()
    let listening = expectation(description: "listening")
    listener.stateUpdateHandler = { state in
      guard case .ready = state else { return }
      listening.fulfill()
    }
    listener.newConnectionHandler = { incoming in
      let connection = PeerConnection(
        connection: incoming, localName: "answerer", greetsOnReady: false)
      connection.setHandlers(
        onReady: { _ in connection.greet() },
        onData: onAnsweredData,
        onClosed: nil)
      answered.set(connection)
      connection.start()
    }
    listener.start(queue: .global())
    wait(for: [listening], timeout: 5)

    guard let port = listener.port else {
      throw XCTSkip("listener has no port")
    }
    let dialled = PeerConnection(
      endpoint: .hostPort(host: "127.0.0.1", port: port), localName: "dialler")
    let greeted = expectation(description: "greeted")
    dialled.setHandlers(
      onReady: { _ in greeted.fulfill() },
      onData: onDialledData,
      onClosed: nil)
    dialled.start()
    wait(for: [greeted], timeout: 10)

    guard let peer = answered.value() else {
      throw XCTSkip("no accepted connection")
    }
    return (dialled, peer, listener)
  }

  func testCarriesSamplesBetweenPeers() throws {
    let received = Received()
    let gotAll = expectation(description: "received all samples")
    let pair = try connectedPair(
      onDialledData: { _ in },
      onAnsweredData: { data in
        if received.append(data) >= 6 {
          gotAll.fulfill()
        }
      })
    defer {
      pair.dialled.cancel()
      pair.answered.cancel()
      pair.listener.cancel()
    }

    // A trailing odd byte must be held back until its pair arrives, so three
    // bytes then one byte has to arrive as two whole Int16 samples.
    pair.dialled.send(Data([1, 2, 3]))
    pair.dialled.send(Data([4]))
    pair.dialled.send(Data([5, 6]))

    wait(for: [gotAll], timeout: 10)
    XCTAssertEqual(received.bytes(), Data([1, 2, 3, 4, 5, 6]))
    XCTAssertTrue(received.chunks().allSatisfy { $0.count % 2 == 0 })
  }

  func testNamesTheCallerInItsHello() throws {
    let name = Holder<String>()
    let listener = try NWListener(using: PeerConnection.parameters())
    let greeted = expectation(description: "greeted")
    let accepted = Holder<PeerConnection>()
    let listening = expectation(description: "listening")
    listener.stateUpdateHandler = { state in
      guard case .ready = state else { return }
      listening.fulfill()
    }
    listener.newConnectionHandler = { incoming in
      let connection = PeerConnection(
        connection: incoming, localName: "answerer", greetsOnReady: false)
      connection.setHandlers(
        onReady: { peerName in
          name.set(peerName)
          greeted.fulfill()
        }, onData: nil, onClosed: nil)
      accepted.set(connection)
      connection.start()
    }
    listener.start(queue: .global())
    wait(for: [listening], timeout: 5)

    let port = try XCTUnwrap(listener.port)
    let dialled = PeerConnection(
      endpoint: .hostPort(host: "127.0.0.1", port: port), localName: "dialler")
    dialled.start()
    defer {
      dialled.cancel()
      accepted.value()?.cancel()
      listener.cancel()
    }

    wait(for: [greeted], timeout: 10)
    XCTAssertEqual(name.value(), "dialler")
  }

  func testDropsBacklogWhileNotConnected() {
    // Nothing is connected, so the queue can only grow: it has to shed the
    // oldest audio rather than buffer a call's worth of it.
    let connection = PeerConnection(
      endpoint: .hostPort(host: "127.0.0.1", port: 9), localName: "dialler")
    let chunk = Data(repeating: 7, count: 3200)
    for _ in 0..<20 {
      connection.send(chunk)
    }
    // 200ms of 16kHz mono Int16 audio is the cap, so almost all of the 64000
    // bytes written must have been dropped rather than queued.
    XCTAssertGreaterThan(connection.stats().dropped, 64000 - 6400 - 3200)
    connection.cancel()
  }
}

private final class Holder<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: T?

  func set(_ value: T) {
    lock.lock()
    stored = value
    lock.unlock()
  }

  func value() -> T? {
    lock.lock()
    defer { lock.unlock() }
    return stored
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

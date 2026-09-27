import Foundation
import Network
import XCTest

@testable import transport

final class PacketTests: XCTestCase {
  func testRoundTripsEveryPacketType() {
    let packets: [Packet] = [
      .hello(identity: "device-id"),
      .audio(seq: 0, payload: Data([9])),
      .audio(seq: 0xfeed_beef, payload: Data(repeating: 7, count: 91)),
      .ping(sentMs: 12345),
      .pong(echoedMs: 0xffff_ffff),
    ]
    for packet in packets {
      XCTAssertEqual(Packet.decode(packet.encoded()), packet)
    }
  }

  func testRejectsTruncatedAndUnknownPackets() {
    XCTAssertNil(Packet.decode(Data()))
    XCTAssertNil(Packet.decode(Data([9, 1, 2, 3, 4])))
    XCTAssertNil(Packet.decode(Data([2, 0, 0])))
    XCTAssertNil(Packet.decode(Data([1, 0, 5, 65])))
  }

  func testAudioHeaderIsFiveBytes() {
    let payload = Data(repeating: 1, count: 90)
    XCTAssertEqual(Packet.audio(seq: 7, payload: payload).encoded().count, payload.count + 5)
  }
}

final class PeerConnectionTests: XCTestCase {
  /// Two connections over the loopback interface, using the same parameters
  /// as a real call, so the DTLS handshake and the hello exchange are covered
  /// along with the audio datagrams.
  private func connectedPair(
    onDialledData: @escaping @Sendable (UInt32, Data) -> Void,
    onAnsweredData: @escaping @Sendable (UInt32, Data) -> Void
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
        connection: incoming, localIdentity: "answerer-id", greetsOnReady: false)
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
      endpoint: .hostPort(host: "127.0.0.1", port: port), localIdentity: "dialler-id")
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

  func testCarriesSequencedAudioBetweenPeers() throws {
    let received = Received()
    let gotAll = expectation(description: "received all packets")
    let pair = try connectedPair(
      onDialledData: { _, _ in },
      onAnsweredData: { seq, data in
        if received.append(seq: seq, data: data) >= 3 {
          gotAll.fulfill()
        }
      })
    defer {
      pair.dialled.cancel()
      pair.answered.cancel()
      pair.listener.cancel()
    }

    pair.dialled.send(Data([1, 2, 3]))
    pair.dialled.send(Data([4]))
    pair.dialled.send(Data([5, 6]))

    wait(for: [gotAll], timeout: 10)
    // Datagrams can reorder even on loopback, so match by sequence number:
    // each payload must arrive whole, exactly as sent, under the seq it was
    // sent with.
    let bySeq = Dictionary(received.packets()) { first, _ in first }
    XCTAssertEqual(bySeq[0], Data([1, 2, 3]))
    XCTAssertEqual(bySeq[1], Data([4]))
    XCTAssertEqual(bySeq[2], Data([5, 6]))
  }

  func testIdentifiesTheCallerInItsHello() throws {
    let identity = Holder<String>()
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
        connection: incoming, localIdentity: "answerer-id", greetsOnReady: false)
      connection.setHandlers(
        onReady: { peerIdentity in
          identity.set(peerIdentity)
          greeted.fulfill()
        }, onData: nil, onClosed: nil)
      accepted.set(connection)
      connection.start()
    }
    listener.start(queue: .global())
    wait(for: [listening], timeout: 5)

    let port = try XCTUnwrap(listener.port)
    let dialled = PeerConnection(
      endpoint: .hostPort(host: "127.0.0.1", port: port), localIdentity: "dialler-id")
    dialled.start()
    defer {
      dialled.cancel()
      accepted.value()?.cancel()
      listener.cancel()
    }

    wait(for: [greeted], timeout: 10)
    XCTAssertEqual(identity.value(), "dialler-id")
  }

  func testMeasuresRoundTripTimeOverPings() throws {
    let pair = try connectedPair(onDialledData: { _, _ in }, onAnsweredData: { _, _ in })
    defer {
      pair.dialled.cancel()
      pair.answered.cancel()
      pair.listener.cancel()
    }

    // Pings repeat every second from both sides once the hellos have crossed.
    let deadline = Date().addingTimeInterval(10)
    while pair.dialled.rttMs() == nil, Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    let rtt = try XCTUnwrap(pair.dialled.rttMs())
    XCTAssertGreaterThanOrEqual(rtt, 0)
    XCTAssertLessThan(rtt, 5000)
  }

  /// The race that stranded a real call: the answerer's hellos were lost, the
  /// caller's pongs (which answer pings regardless of the hello) arrived, and
  /// the answerer treated the pong as proof and stopped retransmitting. A
  /// peer that pongs but never acknowledges the hello must keep receiving it.
  func testKeepsRetransmittingHelloWhenOnlyPongsComeBack() throws {
    let listener = try NWListener(using: PeerConnection.parameters())
    let answered = Holder<PeerConnection>()
    let listening = expectation(description: "listening")
    listener.stateUpdateHandler = { state in
      guard case .ready = state else { return }
      listening.fulfill()
    }
    listener.newConnectionHandler = { incoming in
      let connection = PeerConnection(
        connection: incoming, localIdentity: "answerer-id", greetsOnReady: false)
      connection.setHandlers(
        onReady: { _ in connection.greet() }, onData: nil, onClosed: nil)
      answered.set(connection)
      connection.start()
    }
    listener.start(queue: .global())
    wait(for: [listening], timeout: 5)
    let port = try XCTUnwrap(listener.port)

    let helloTimes = Times()
    let pongedAt = Holder<Date>()
    let caller = NWConnection(
      to: .hostPort(host: "127.0.0.1", port: port), using: PeerConnection.parameters())
    let sendable = SendableBox(caller)
    @Sendable func receiveLoop() {
      sendable.value.receiveMessage { data, _, _, error in
        if let data, let packet = Packet.decode(data) {
          switch packet {
          case .hello:
            helloTimes.append(Date())
          case .ping(let sentMs):
            sendable.value.send(
              content: Packet.pong(echoedMs: sentMs).encoded(), completion: .idempotent)
            if pongedAt.value() == nil {
              pongedAt.set(Date())
            }
          default:
            break
          }
        }
        guard error == nil else { return }
        receiveLoop()
      }
    }
    caller.stateUpdateHandler = { state in
      guard case .ready = state else { return }
      sendable.value.send(
        content: Packet.hello(identity: "caller-id").encoded(), completion: .idempotent)
      receiveLoop()
    }
    caller.start(queue: .global())
    defer {
      caller.cancel()
      answered.value()?.cancel()
      listener.cancel()
    }

    // The answerer pings as soon as it has greeted, so the first pong lands
    // within a couple of seconds; hellos must still be arriving well after.
    let deadline = Date().addingTimeInterval(10)
    while pongedAt.value() == nil, Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    let ponged = try XCTUnwrap(pongedAt.value())
    RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    let hellosAfterPong = helloTimes.all().filter {
      $0.timeIntervalSince(ponged) > 0.3
    }
    XCTAssertGreaterThanOrEqual(hellosAfterPong.count, 3)
  }

  func testDropsAudioWhileNotConnected() {
    // Nothing is connected: audio is stale the moment a connection would come
    // up, so it must be dropped on the spot rather than queued.
    let connection = PeerConnection(
      endpoint: .hostPort(host: "127.0.0.1", port: 9), localIdentity: "dialler-id")
    let payload = Data(repeating: 7, count: 90)
    for _ in 0..<20 {
      connection.send(payload)
    }
    XCTAssertEqual(connection.stats().dropped, 20 * payload.count)
    XCTAssertEqual(connection.stats().sent, 0)
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

private final class Times: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [Date] = []

  func append(_ date: Date) {
    lock.lock()
    stored.append(date)
    lock.unlock()
  }

  func all() -> [Date] {
    lock.lock()
    defer { lock.unlock() }
    return stored
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

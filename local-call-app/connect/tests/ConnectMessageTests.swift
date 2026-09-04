import Foundation
import XCTest

@testable import connect

final class ConnectCodecTests: XCTestCase {
  private let sender = UUID()
  private let secret = ConnectCodec.newSecret()

  private func open(_ data: Data, now: Date = Date(), secret: Data?) throws -> ConnectFrame {
    try ConnectCodec.open(data, now: now) { _ in secret }
  }

  func testRoundTrip() throws {
    let callId = UUID()
    let messages: [ConnectMessage] = [
      .invite(callId: callId, name: "Blu's iPhone"),
      .cancel(callId: callId),
      .accept(callId: callId),
      .decline(callId: callId),
      .busy(callId: callId),
      .silenced(callId: callId),
    ]
    for message in messages {
      let data = ConnectCodec.seal(message, senderId: sender, secret: secret)
      let frame = try open(data, secret: secret)
      XCTAssertEqual(frame.senderId, sender)
      XCTAssertEqual(frame.message, message)
    }
  }

  func testPairingIsUnauthenticated() throws {
    let request = ConnectMessage.pairRequest(name: "iPad", secret: secret)
    let frame = try open(
      ConnectCodec.seal(request, senderId: sender, secret: nil), secret: nil)
    XCTAssertEqual(frame.message, request)

    let accept = ConnectMessage.pairAccept(name: "iPad")
    XCTAssertEqual(
      try open(ConnectCodec.seal(accept, senderId: sender, secret: nil), secret: nil).message,
      accept)

    let decline = ConnectMessage.pairDecline
    XCTAssertEqual(
      try open(ConnectCodec.seal(decline, senderId: sender, secret: nil), secret: nil).message,
      decline)
  }

  func testRejects() {
    let data = ConnectCodec.seal(.cancel(callId: UUID()), senderId: sender, secret: secret)

    func error(_ body: @autoclosure () throws -> ConnectFrame) -> ConnectFrameError? {
      do {
        _ = try body()
        return nil
      } catch let error as ConnectFrameError {
        return error
      } catch {
        return nil
      }
    }

    XCTAssertEqual(error(try open(data, secret: ConnectCodec.newSecret())), .badSignature)
    XCTAssertEqual(error(try open(data, secret: nil)), .unknownSender)
    XCTAssertEqual(
      error(try open(data, now: Date().addingTimeInterval(120), secret: secret)), .expired)
    XCTAssertEqual(error(try open(data.dropLast(4), secret: secret)), .missingSignature)
    XCTAssertEqual(error(try open(data.prefix(10), secret: secret)), .truncated)

    var wrongVersion = data
    wrongVersion[0] = 9
    XCTAssertEqual(error(try open(wrongVersion, secret: secret)), .badVersion)

    var tampered = data
    tampered[30] = tampered[30] &+ 1
    XCTAssertNotNil(error(try open(tampered, secret: secret)))
  }

  func testUnsignedCallMessageIsRejected() {
    XCTAssertThrowsError(
      try open(
        ConnectCodec.seal(.cancel(callId: UUID()), senderId: sender, secret: nil), secret: secret))
  }

  func testNamesAreTrimmedToFitANotification() throws {
    let long = String(repeating: "é", count: 40)
    let data = ConnectCodec.seal(
      .invite(callId: UUID(), name: long), senderId: sender, secret: secret)
    XCTAssertLessThanOrEqual(data.count, 128)
    guard case .invite(_, let name) = try open(data, secret: secret).message else {
      return XCTFail("not an invite")
    }
    XCTAssertLessThanOrEqual(name.utf8.count, ConnectCodec.maxNameBytes)
    XCTAssertTrue(long.hasPrefix(name))
  }
}

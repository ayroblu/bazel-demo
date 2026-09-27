import XCTest

@testable import transport

final class TransportModeTests: XCTestCase {
  func testAwdlDoesNotUseL2cap() {
    XCTAssertFalse(TransportMode.awdl.usesL2cap)
  }

  func testL2capUsesL2cap() {
    XCTAssertTrue(TransportMode.l2cap.usesL2cap)
  }
}

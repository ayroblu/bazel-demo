import SwiftLib
import XCTest

class BridgeTests: XCTestCase {
  func testBridge_Success() {
    XCTAssertEqual(SwiftRust.add(1, 2), 3)
  }
}

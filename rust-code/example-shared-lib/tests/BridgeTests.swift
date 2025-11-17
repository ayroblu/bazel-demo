import XCTest
import example

class BridgeTests: XCTestCase {
  func testBridge_Success() {
    XCTAssertEqual(printAndAdd(a: 1, b: 2), 3)
  }
}

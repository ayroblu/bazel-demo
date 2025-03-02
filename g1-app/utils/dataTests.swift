import XCTest

@testable import utils

class UtilsTests: XCTestCase {
  func testExample() {
    XCTAssertEqual(2 + 2, 4, "Basic math should work")
  }

  func testArrayChunk() {
    let result = [1, 2, 3, 4, 5, 6, 7].chunk(into: 2)
    XCTAssertEqual(result, [[1, 2], [3, 4], [5, 6], [7]])
  }

  static var allTests = [
    ("testExample", testExample),
    ("testMyLibraryFunction", testArrayChunk),
  ]
}

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

  func testRunLengthEncode() {
    let data: [UInt8] = [0x01, 0x20, 0x20, 0x20, 0x05, 0x05]
    let result = data.runLengthEncode()
    XCTAssertEqual(result, [0x01, 0x01, 0x03, 0x20, 0x02, 0x05])
  }

  func testRunLengthDecode() {
    let data: [UInt8] = [0x01, 0x01, 0x03, 0x20, 0x02, 0x05]
    let result = data.runLengthDecode()
    XCTAssertEqual(result, [0x01, 0x20, 0x20, 0x20, 0x05, 0x05])
  }
}

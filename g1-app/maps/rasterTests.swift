import MySnapshotTesting
import XCTest

@testable import maps

class RasterTests: XCTestCase {
  func testExample() {
    XCTAssertEqual(2 + 2, 4, "Basic math should work")
  }

  func testRasterPoint() {
    var mapBoard = MapBoard(width: 3, height: 2)
    mapBoard.rasterPoint(1, 2)
    let board = mapBoard.board.toBoardString()
    assertSnapshot(of: board, as: .lines)
  }
}

extension Array where Element == [Bool] {
  func toBoardString() -> String {
    let rowStrings = self.map { row in
      row.map { $0 ? "x" : " " }.joined()
    }

    return rowStrings.joined(separator: "\n")
  }
}

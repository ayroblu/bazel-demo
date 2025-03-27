import MySnapshotTesting
import XCTest

@testable import maps

class RasterTests: XCTestCase {
  func testDrawLine() {
    var mapBoard = MapBoard(width: 13, height: 7)
    mapBoard.drawLine(from: (1, 1), to: (11, 5))
    let board = mapBoard.board.toBoardString()
    // https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm
    assertSnapshot(of: board, as: .lines)
  }

  func testDrawLineReverse() {
    var mapBoard = MapBoard(width: 13, height: 7)
    mapBoard.drawLine(from: (11, 5), to: (1, 1))
    let board = mapBoard.board.toBoardString()
    // https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm
    assertSnapshot(of: board, as: .lines)
  }

  func testDrawLine2() {
    var mapBoard = MapBoard(width: 13, height: 7)
    mapBoard.drawLine(from: (1, 5), to: (11, 1))
    let board = mapBoard.board.toBoardString()
    // https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm
    assertSnapshot(of: board, as: .lines)
  }

  func testDrawLineThickness() {
    var mapBoard = MapBoard(width: 14, height: 8)
    mapBoard.drawLine(from: (1, 1), to: (11, 5), lineWidth: 2)
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

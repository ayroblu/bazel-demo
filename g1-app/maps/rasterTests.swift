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

  func testDrawArrow() {
    var mapBoard = MapBoard(width: 8, height: 8)
    mapBoard.drawArrow(position: (0, 2), dim: (8, 4))
    // mapBoard.rotate(angle: -30 * .pi / 180.0)
    let board = mapBoard.board.toBoardString()
    assertSnapshot(of: board, as: .lines)
  }

  func testCircleOutline() {
    var mapBoard = MapBoard(width: 20, height: 20)
    mapBoard.drawCircleOutline(pos: (9, 9), radius: 8)
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

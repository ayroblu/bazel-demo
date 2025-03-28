import Foundation

extension MapBoard {
  mutating func rotate(angle: Double) {
    var rotated = Array(repeating: Array(repeating: false, count: width), count: height)
    let centerX = Double(width - 1) / 2.0
    let centerY = Double(height - 1) / 2.0

    for i in 0..<height {
      for j in 0..<width {
        // Translate to center
        let x = Double(j) - centerX
        let y = Double(i) - centerY

        // Apply rotation formula
        let newX = x * cos(angle) - y * sin(angle)
        let newY = x * sin(angle) + y * cos(angle)

        // Translate back
        let origX = Int(round(newX + centerX))
        let origY = Int(round(newY + centerY))

        // Check if the original coordinates are within bounds
        if origX >= 0 && origX < width && origY >= 0 && origY < height {
          rotated[i][j] = board[origY][origX]
        }
      }
    }
    board = rotated
  }

  mutating func merge(_ mapBoard: MapBoard, pos: (x: Int, y: Int)) {
    for x in 0..<mapBoard.width {
      for y in 0..<mapBoard.height {
        let item = mapBoard.board[y][x]
        guard item else { continue }
        let x0 = pos.x + x
        let y0 = pos.y + y
        guard x0 >= 0 && x0 < width else { continue }
        guard y0 >= 0 && y0 < height else { continue }
        board[y0][x0] = item
      }
    }
  }

  init(_ mapBoard: MapBoard) {
    var newMapBoard = MapBoard(width: mapBoard.width, height: mapBoard.height)
    newMapBoard.merge(mapBoard, pos: (0, 0))
    self = newMapBoard
  }
}

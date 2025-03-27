import Foundation

extension MapBoard {
  mutating func drawLine(
    from start: (x: Int, y: Int),
    to end: (x: Int, y: Int),
    lineWidth: Int = 1
  ) {
    guard
      start.x >= 0 && start.x < width && start.y >= 0 && start.y < height && end.x >= 0
        && end.x < width && end.y >= 0 && end.y < height
    else {
      // print("Line coordinates out of board bounds")
      return
    }

    // Bresenham's line algorithm with width
    let dx = abs(end.x - start.x)
    let dy = abs(end.y - start.y)
    let sx = start.x < end.x ? 1 : -1
    let sy = start.y < end.y ? 1 : -1

    var err = dx - dy
    var currentX = start.x
    var currentY = start.y

    while true {
      // Draw a square of points around the line with given width
      // 1:  0...0
      // 2:  0...1
      // 3: -1...1
      // 4: -1...2
      // 5: -2...2
      for offsetX in -((lineWidth - 1) / 2)...(lineWidth / 2) {
        for offsetY in -((lineWidth - 1) / 2)...(lineWidth / 2) {
          let plotX = currentX + offsetX
          let plotY = currentY + offsetY

          // Ensure the point is within board bounds
          if plotX >= 0 && plotX < width && plotY >= 0 && plotY < height {
            board[plotY][plotX] = true
          }
        }
      }

      if currentX == end.x && currentY == end.y {
        break
      }

      let e2 = 2 * err
      if e2 > -dy {
        err -= dy
        currentX += sx
      }
      if e2 < dx {
        err += dx
        currentY += sy
      }
    }
  }
}

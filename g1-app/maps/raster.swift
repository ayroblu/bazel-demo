import Foundation

extension MapBoard {
  mutating func drawLine(
    from start: (x: Int, y: Int),
    to end: (x: Int, y: Int),
    lineWidth: Int = 1
  ) {
    guard
      start.x >= -width && start.x < width * 2 && start.y >= -height && start.y < height * 2
        && end.x >= -width && end.x < width * 2 && end.y >= -height && end.y < height * 2
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

  mutating func drawArrow(position: (x: Int, y: Int), dim: (w: Int, h: Int), lineWidth: Int = 2) {
    let (x, y) = position
    let (w, h) = dim
    let wo = w - lineWidth
    let ho = h - 1
    let midX = Double(wo) / 2
    for r in 0..<lineWidth {
      drawLine(from: (x + r, y + ho), to: (x + Int(floor(midX)) + r, y))
      drawLine(from: (x + wo + r, y + ho), to: (x + Int(ceil(midX)) + r, y))
    }
  }

  /// midpoint circle algorithm
  mutating func drawCircleOutline(pos: (centerX: Int, centerY: Int), radius: Int) {
    // Check if radius is negative
    guard radius >= 0 else { return }

    let (centerX, centerY) = pos
    let rows = height
    let cols = width

    func setPoint(_ x: Int, _ y: Int) {
      if x >= 0 && x < cols && y >= 0 && y < rows {
        board[y][x] = true
      }
    }

    // Special case for radius 0 (single point)
    if radius == 0 {
      setPoint(centerX, centerY)
      return
    }

    var x = radius
    var y = 0
    var err = 0

    while x >= y {
      setPoint(centerX + x, centerY + y)
      setPoint(centerX + y, centerY + x)
      setPoint(centerX - y, centerY + x)
      setPoint(centerX - x, centerY + y)
      setPoint(centerX - x, centerY - y)
      setPoint(centerX - y, centerY - x)
      setPoint(centerX + y, centerY - x)
      setPoint(centerX + x, centerY - y)

      y += 1
      err += 1 + 2 * y
      if 2 * (err - x) + 1 > 0 {
        x -= 1
        err -= 1 - 2 * x
      }
    }
  }
}

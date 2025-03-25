import Foundation

struct MapBoard {
  let width: Int
  let height: Int
  var board: [[Bool]]
}

extension MapBoard {
  mutating func rasterLine(_ a: (Double, Double), _ b: (Double, Double)) {
    let (ax, ay) = a
    let (bx, by) = b
    let lenX = abs(bx - ax)
    let lenY = abs(by - ay)
    let isVertical = lenY > lenX
    // round ax, ay, set board[x][y] = true
    let dir =
      isVertical
      ? ay > by ? (((bx - ax) / lenY), -1) : (((bx - ax) / lenY), 1)
      : ax > bx ? (-1, ((by - ay) / lenX)) : (1, ((by - ay) / lenX))
    func rangeWidth(_ v: Double) -> Range<Int> {
      let upper = Int(round(v)) + (width - 1) / 2
      let lower = upper - width
      return lower..<upper
    }

    // board[round(x + dirX)][round(y + dirY)] = true
    // var counter = width
    if isVertical {
      // for _ in ay..<by {
      let x = ax
      let y = ay
      for dx in rangeWidth(x) {
        // board[x + dx][y] = true
        rasterPoint(x + Double(dx), y)
      }
      // }
    }
  }

  mutating func rasterPoint(_ x: Double, _ y: Double) {
    board[Int(round(x))][Int(round(y))] = true
  }
}

import Foundation

extension MapBoard {
  mutating func render(data: OverpassResult, bounds: ElementBounds) {
    for road in data.elements {
      for (a, b) in zip(road.geometry, road.geometry.dropFirst()) {
        if let from = mapPoint(point: a, bounds: bounds),
          let to = mapPoint(point: b, bounds: bounds)
        {
          drawLine(from: from, to: to, lineWidth: road.tags.maxspeed != nil ? 3 : 1)
        }
      }
    }
  }

  private func mapPoint(point: LatLng, bounds: ElementBounds) -> (x: Int, y: Int)? {
    let lat = point.lat
    let lng = point.lon
    // Note a small bug here when crossing from "eastern" to "western" hemisphere
    guard
      lat >= bounds.minlat && lat <= bounds.maxlat && lng >= bounds.minlng && lng <= bounds.maxlng
    else { return nil }
    let dlat = bounds.maxlat - bounds.minlat
    let dlng = bounds.maxlng - bounds.minlng
    return (
      Int(round((lng - bounds.minlng) / dlng * Double(width))),
      Int(round((bounds.maxlat - lat) / dlat * Double(height)))
    )
  }

  mutating func crop(start: (x: Int, y: Int), dim: (newWidth: Int, newHeight: Int)) {
    let (x, y) = start
    let (newWidth, newHeight) = dim
    guard x >= 0 && y >= 0 else { return }
    guard newWidth > 0 && newHeight > 0 else { return }
    guard x + newWidth <= width && y + newHeight <= height else { return }

    let newBoard: [[Bool]] = board[y..<(y + newHeight)].map { row in
      Array(row[x..<(x + newWidth)])
    }

    board = newBoard
    width = newWidth
    height = newHeight
  }
}

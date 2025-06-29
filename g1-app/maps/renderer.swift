import Foundation
import MapKit

extension MapBoard {
  mutating func render(data: OverpassResult, bounds: ElementBounds) {
    for road in data.elements {
      for (a, b) in zip(road.geometry, road.geometry.dropFirst()) {
        let from = mapPoint(point: a, bounds: bounds)
        let to = mapPoint(point: b, bounds: bounds)
        drawLine(from: from, to: to, lineWidth: road.tags.maxspeed != nil ? 3 : 1)
      }
    }
  }

  private func mapPoint(point: LatLng, bounds: ElementBounds) -> (x: Int, y: Int) {
    let point = (point.lat, point.lon)
    return mapPoint(point: point, bounds: bounds)
  }
  private func mapPoint(point: CLLocationCoordinate2D, bounds: ElementBounds) -> (x: Int, y: Int) {
    let point = (point.latitude, point.longitude)
    return mapPoint(point: point, bounds: bounds)
  }
  private func mapPoint(point: (Double, Double), bounds: ElementBounds) -> (x: Int, y: Int) {
    return getPosInBounds(dim: (width, height), pos: point, bounds: bounds)
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

  mutating func renderRoute(route: MKRoute, bounds: ElementBounds) {
    let points = route.polyline.points()
    for i in 1..<route.polyline.pointCount {
      let pointA = points[i - 1]
      let pointB = points[i]
      let from = mapPoint(point: pointA.coordinate, bounds: bounds)
      let to = mapPoint(point: pointB.coordinate, bounds: bounds)
      drawLine(from: from, to: to, lineWidth: 2)
    }

    // Triangle
    let lastPoint = points[route.polyline.pointCount - 1]
    let lastLatLng = LatLng(lat: lastPoint.coordinate.latitude, lon: lastPoint.coordinate.longitude)
    let (x, y) = mapPoint(point: lastLatLng, bounds: bounds)
    drawLine(from: (x, y - 2), to: (x - 4, y + 2))
    drawLine(from: (x, y - 2), to: (x + 4, y + 2))
    drawLine(from: (x - 4, y + 2), to: (x + 4, y + 2))
  }

  mutating func renderDashedPath(
    path: [((Double, Double), (Double, Double))], bounds: ElementBounds
  ) {
    var isVisible = true
    for (a, b) in path {
      if isVisible {
        let from = mapPoint(point: a, bounds: bounds)
        let to = mapPoint(point: b, bounds: bounds)
        drawLine(from: from, to: to, lineWidth: 2)
      }
      isVisible = !isVisible
    }
  }
}

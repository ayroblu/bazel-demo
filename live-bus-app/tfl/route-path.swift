import Foundation

public struct RoutePath: Hashable, Sendable {
  public let direction: String
  public let coordinates: [Coordinate]
  public let stops: [PathStop]
  let distances: [Double]

  func point(at distance: Double) -> (coordinate: Coordinate, heading: Double) {
    let clamped = min(max(distance, 0), distances[distances.count - 1])
    var low = 0
    var high = distances.count - 1
    while high - low > 1 {
      let mid = (low + high) / 2
      if distances[mid] <= clamped {
        low = mid
      } else {
        high = mid
      }
    }
    let a = coordinates[low]
    let b = coordinates[high]
    let length = distances[high] - distances[low]
    let t = length > 0 ? (clamped - distances[low]) / length : 0
    return (
      Coordinate(lat: a.lat + (b.lat - a.lat) * t, lon: a.lon + (b.lon - a.lon) * t),
      bearing(from: a, to: b)
    )
  }
}

public struct PathStop: Hashable, Sendable {
  public let stop: BusStop
  public let distance: Double
}

func makeRoutePaths(direction: String, lineStrings: [String], sequences: [[BusStop]])
  -> [RoutePath]
{
  let polylines = lineStrings.flatMap(parseLineString).filter { $0.count > 1 }.map(
    PlanarPolyline.init)
  guard !polylines.isEmpty else { return [] }
  var stopsByPolyline = Array(repeating: [PathStop](), count: polylines.count)
  for stops in sequences where !stops.isEmpty {
    let projections = polylines.map { $0.project(stops) }
    let best = projections.indices.min { projections[$0].error < projections[$1].error }!
    stopsByPolyline[best] += zip(stops, projections[best].distances).map {
      PathStop(stop: $0, distance: $1)
    }
  }
  return polylines.indices.compactMap { i in
    guard !stopsByPolyline[i].isEmpty else { return nil }
    return RoutePath(
      direction: direction, coordinates: polylines[i].coordinates,
      stops: uniqueStops(stopsByPolyline[i]), distances: polylines[i].distances)
  }
}

private func bearing(from a: Coordinate, to b: Coordinate) -> Double {
  let dx = (b.lon - a.lon) * cos(a.lat * .pi / 180)
  let dy = b.lat - a.lat
  return atan2(dx, dy) * 180 / .pi
}

private func parseLineString(_ lineString: String) -> [[Coordinate]] {
  guard let lines = try? JSONDecoder().decode([[[Double]]].self, from: Data(lineString.utf8))
  else { return [] }
  return lines.map { line in
    line.filter { $0.count >= 2 }.map { Coordinate(lat: $0[1], lon: $0[0]) }
  }
}

private struct PlanarPolyline {
  let coordinates: [Coordinate]
  let points: [SIMD2<Double>]
  let distances: [Double]

  init(_ coordinates: [Coordinate]) {
    self.coordinates = coordinates
    points = coordinates.map(planar)
    var total = 0.0
    distances =
      [0]
      + zip(points, points.dropFirst()).map { a, b in
        total += length(b - a)
        return total
      }
  }

  func project(_ stops: [BusStop]) -> (distances: [Double], error: Double) {
    var start = 0
    var error = 0.0
    var result: [Double] = []
    for stop in stops {
      let p = planar(stop.coordinate)
      let candidates = (start..<points.count - 1).map { i in
        let a = points[i]
        let ab = points[i + 1] - a
        let lengthSquared = (ab * ab).sum()
        let t = lengthSquared > 0 ? min(max(((p - a) * ab).sum() / lengthSquared, 0), 1) : 0
        return (
          segment: i, gap: length(p - (a + t * ab)),
          along: distances[i] + t * lengthSquared.squareRoot()
        )
      }
      let minGap = candidates.map(\.gap).min()!
      let pick = candidates.first { $0.gap <= minGap + 25 }!
      start = pick.segment
      error += pick.gap
      result.append(pick.along)
    }
    return (result, error)
  }
}

private func planar(_ coordinate: Coordinate) -> SIMD2<Double> {
  SIMD2(
    coordinate.lon * metersPerDegree * cos(coordinate.lat * .pi / 180),
    coordinate.lat * metersPerDegree)
}

private let metersPerDegree = 111_320.0

private func length(_ v: SIMD2<Double>) -> Double {
  (v * v).sum().squareRoot()
}

private func uniqueStops(_ stops: [PathStop]) -> [PathStop] {
  var result: [PathStop] = []
  for stop in stops.sorted(by: { $0.distance < $1.distance })
  where !result.contains(where: {
    $0.stop.id == stop.stop.id && abs($0.distance - stop.distance) < 50
  }) {
    result.append(stop)
  }
  return result
}

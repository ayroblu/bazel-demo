import Foundation

public struct VehicleTrack: Hashable, Sendable, Identifiable {
  public let id: String
  public let lineId: String
  public let lineName: String
  public let direction: String
  public let destination: String
  public let stops: [TrackStop]
  let path: RoutePath

  public func position(at date: Date) -> BusPosition? {
    guard let first = stops.first, let last = stops.last,
      date < last.arrival.addingTimeInterval(60)
    else { return nil }
    let distance: Double
    if date <= first.arrival {
      distance = first.distance
    } else if let next = stops.firstIndex(where: { $0.arrival > date }) {
      let from = stops[next - 1]
      let to = stops[next]
      let t = date.timeIntervalSince(from.arrival) / to.arrival.timeIntervalSince(from.arrival)
      distance = from.distance + (to.distance - from.distance) * t
    } else {
      distance = last.distance
    }
    let point = path.point(at: distance)
    return BusPosition(
      id: id, lineName: lineName, coordinate: point.coordinate, heading: point.heading,
      direction: direction)
  }
}

public struct TrackStop: Hashable, Sendable, Identifiable {
  public let stop: BusStop
  public let distance: Double
  public let arrival: Date
  public let isEstimated: Bool

  public var id: Double { distance }
}

public struct BusPosition: Hashable, Sendable, Identifiable {
  public let id: String
  public let lineName: String
  public let coordinate: Coordinate
  public let heading: Double
  public let direction: String
}

public func makeVehicleTracks(route: BusRoute, arrivals: [Arrival], now: Date) -> [VehicleTrack] {
  Dictionary(grouping: arrivals.filter { !$0.vehicleId.isEmpty }, by: \.vehicleId)
    .compactMap { makeTrack(route: route, arrivals: $1, now: now) }
    .sorted { $0.id < $1.id }
}

private let defaultSpeed = 4.5
private let speedRange = 2.0...12.0
private let maxTerminusWait: TimeInterval = 120

private func makeTrack(route: BusRoute, arrivals: [Arrival], now: Date) -> VehicleTrack? {
  let sorted = arrivals.sorted { $0.expectedArrival < $1.expectedArrival }
  guard let first = sorted.first else { return nil }
  let trip = sorted.filter { $0.direction == first.direction }
  let tripStopIds = Set(trip.map(\.stopId))
  let candidates = route.paths.filter { $0.direction == first.direction }
  guard
    let path = (candidates.isEmpty ? route.paths : candidates).max(by: {
      $0.stops.count(where: { tripStopIds.contains($0.stop.id) })
        < $1.stops.count(where: { tripStopIds.contains($0.stop.id) })
    })
  else { return nil }

  var stops: [TrackStop] = []
  for arrival in trip {
    let minDistance = stops.last?.distance ?? -1
    guard
      let pathStop = path.stops.first(where: {
        $0.stop.id == arrival.stopId && $0.distance > minDistance
      })
    else { continue }
    stops.append(
      TrackStop(
        stop: pathStop.stop, distance: pathStop.distance, arrival: arrival.expectedArrival,
        isEstimated: false))
  }
  guard let next = stops.first else { return nil }

  if let previous = path.stops.last(where: { $0.distance < next.distance - 1 }) {
    stops.insert(
      TrackStop(
        stop: previous.stop, distance: previous.distance,
        arrival: next.arrival.addingTimeInterval(
          -(next.distance - previous.distance) / estimateSpeed(stops)),
        isEstimated: true), at: 0)
  } else if next.arrival.timeIntervalSince(now) > maxTerminusWait {
    return nil
  }
  return VehicleTrack(
    id: first.vehicleId, lineId: first.lineId, lineName: first.lineName,
    direction: first.direction,
    destination: first.destination, stops: stops, path: path)
}

private func estimateSpeed(_ stops: [TrackStop]) -> Double {
  guard stops.count > 1 else { return defaultSpeed }
  let duration = stops[1].arrival.timeIntervalSince(stops[0].arrival)
  guard duration > 0 else { return defaultSpeed }
  return min(
    max((stops[1].distance - stops[0].distance) / duration, speedRange.lowerBound),
    speedRange.upperBound)
}

import CoreLocation
import Foundation
import Log
import MapKit
import Observation
import tfl

@Observable final class BusMapModel {
  var lines: [BusLine] = []
  var nearbyStops: [BusStop] = []
  var isZoomedIn = false
  var showsStopLetters = false
  private(set) var allStops: [BusStop] = []
  private(set) var allStopsVersion = 0
  var selectedLineId: String?
  var route: BusRoute?
  var tracks: [VehicleTrack] = []
  var stopTracks: [VehicleTrack] = []
  var lastUpdate: Date?
  var errorMessage: String?
  private var routeTask: Task<Void, Never>?
  private var stopTask: Task<Void, Never>?
  private var routeCache: [String: BusRoute] = [:]
  private var arrivalsCache: [String: (arrivals: [Arrival], fetchedAt: Date)] = [:]
  private var stopsTask: Task<Void, Never>?
  private var lastStopsQuery: (center: CLLocation, radius: Int)?
  private var hasCheckedStopCache = false
  private var visibleRegion: MKCoordinateRegion?

  func loadLines() async {
    do {
      lines = try await getBusLines()
    } catch {
      report(error)
    }
  }

  func loadAllStops() async {
    let cached = await loadCachedStops()
    hasCheckedStopCache = true
    if let cached {
      setAllStops(cached.stops)
      guard cached.fetchedAt.addingTimeInterval(stopsRefreshInterval) < Date() else { return }
    } else if let visibleRegion {
      cameraChanged(region: visibleRegion)
    }
    do {
      setAllStops(try await downloadAllStops().stops)
    } catch {
      log("bus stop download failed", error)
    }
  }

  func showRoute(lineId: String) {
    routeTask?.cancel()
    selectedLineId = lineId
    route = nil
    tracks = []
    lastUpdate = nil
    errorMessage = nil
    routeTask = Task {
      do {
        let route = try await loadRoute(lineId: lineId)
        guard !Task.isCancelled else { return }
        self.route = route
        if let cached = arrivalsCache[lineId],
          cached.fetchedAt.addingTimeInterval(arrivalsRefreshInterval) > Date()
        {
          showArrivals(cached.arrivals, route: route, fetchedAt: cached.fetchedAt)
          try await Task.sleep(
            for: .seconds(
              cached.fetchedAt.addingTimeInterval(arrivalsRefreshInterval).timeIntervalSinceNow))
        }
        while !Task.isCancelled {
          await refreshArrivals(route: route)
          try await Task.sleep(for: .seconds(arrivalsRefreshInterval))
        }
      } catch {
        guard !Task.isCancelled else { return }
        report(error)
      }
    }
  }

  func focusStop(_ stop: BusStop) {
    stopTask?.cancel()
    stopTracks = []
    guard !stop.lineIds.isEmpty else { return }
    stopTask = Task {
      while !Task.isCancelled {
        do {
          _ = try await loadArrivals(lineIds: stop.lineIds)
        } catch {
          log("stop arrivals failed", stop.lineIds, error)
        }
        updateStopTracks(stop)
        for lineId in stop.lineIds where routeCache[lineId] == nil {
          guard !Task.isCancelled else { return }
          do {
            _ = try await loadRoute(lineId: lineId)
            updateStopTracks(stop)
          } catch {
            log("route prefetch failed", lineId, error)
          }
        }
        try? await Task.sleep(for: .seconds(arrivalsRefreshInterval))
      }
    }
  }

  func unfocusStop() {
    stopTask?.cancel()
    stopTracks = []
  }

  func clearRoute() {
    routeTask?.cancel()
    selectedLineId = nil
    route = nil
    tracks = []
    lastUpdate = nil
    errorMessage = nil
  }

  func cameraChanged(region: MKCoordinateRegion) {
    let height = region.span.latitudeDelta * metersPerDegree
    let width =
      region.span.longitudeDelta * metersPerDegree * cos(region.center.latitude * .pi / 180)
    isZoomedIn = min(width, height) < maxRouteStopsSpan
    showsStopLetters = min(width, height) < maxStopLettersSpan
    visibleRegion = region
    guard hasCheckedStopCache, showsStopLetters else { return }
    guard allStops.isEmpty else {
      nearbyStops = stopsInVisibleRegion()
      return
    }
    let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
    let radius = min(max(Int((width * width + height * height).squareRoot() / 2), 250), 1000)
    if let last = lastStopsQuery, radius <= last.radius,
      center.distance(from: last.center) < Double(last.radius) / 4
    {
      return
    }
    stopsTask?.cancel()
    stopsTask = Task {
      do {
        let stops = try await getStopsNear(Coordinate(region.center), radius: radius)
        guard !Task.isCancelled else { return }
        nearbyStops = stops
        lastStopsQuery = (center, radius)
      } catch {
        guard !Task.isCancelled else { return }
        report(error)
      }
    }
  }

  func openStop(id: String) async -> BusStop? {
    if let stop = allStops.first(where: { $0.id == id }) {
      return stop
    }
    do {
      return try await getStop(id: id)
    } catch {
      report(error)
      return nil
    }
  }

  func nearbyLines(from location: CLLocation?) -> [BusLine] {
    let origin = location ?? lastStopsQuery?.center
    let stops =
      origin.map { origin in
        nearbyStops.sorted { distance($0, origin) < distance($1, origin) }
      } ?? nearbyStops
    let linesById = Dictionary(lines.map { ($0.id, $0) }) { first, _ in first }
    var seen = Set<String>()
    return stops.flatMap(\.lineIds).filter { seen.insert($0).inserted }.compactMap {
      linesById[$0]
    }
  }

  private func setAllStops(_ stops: [BusStop]) {
    allStops = stops
    allStopsVersion += 1
    stopsTask?.cancel()
    nearbyStops = stopsInVisibleRegion()
  }

  private func stopsInVisibleRegion() -> [BusStop] {
    guard let region = visibleRegion else { return [] }
    let latitudeRange = region.span.latitudeDelta * 0.75
    let longitudeRange = region.span.longitudeDelta * 0.75
    return allStops.filter {
      abs($0.coordinate.lat - region.center.latitude) < latitudeRange
        && abs($0.coordinate.lon - region.center.longitude) < longitudeRange
    }
  }

  private func loadRoute(lineId: String) async throws -> BusRoute {
    if let route = routeCache[lineId] {
      return route
    }
    let route = try await getBusRoute(lineId: lineId)
    routeCache[lineId] = route
    return route
  }

  private func loadArrivals(lineIds: [String]) async throws -> [Arrival] {
    let arrivals = try await getLineArrivals(lineIds: lineIds)
    let fetchedAt = Date()
    let arrivalsByLine = Dictionary(grouping: arrivals, by: \.lineId)
    for lineId in lineIds {
      arrivalsCache[lineId] = (arrivalsByLine[lineId] ?? [], fetchedAt)
    }
    return arrivals
  }

  private func refreshArrivals(route: BusRoute) async {
    do {
      let arrivals = try await loadArrivals(lineIds: [route.lineId])
      guard !Task.isCancelled else { return }
      showArrivals(arrivals, route: route, fetchedAt: Date())
      errorMessage = nil
    } catch {
      guard !Task.isCancelled else { return }
      report(error)
    }
  }

  private func updateStopTracks(_ stop: BusStop) {
    guard !Task.isCancelled else { return }
    let now = Date()
    stopTracks = stop.lineIds.flatMap { lineId -> [VehicleTrack] in
      guard let route = routeCache[lineId], let arrivals = arrivalsCache[lineId]?.arrivals else {
        return []
      }
      let approaching = Set(
        arrivals.filter { $0.stopId == stop.id && $0.expectedArrival > now }.map(\.vehicleId))
      return makeVehicleTracks(
        route: route, arrivals: arrivals.filter { approaching.contains($0.vehicleId) }, now: now)
    }
  }

  private func showArrivals(_ arrivals: [Arrival], route: BusRoute, fetchedAt: Date) {
    tracks = makeVehicleTracks(route: route, arrivals: arrivals, now: Date())
    lastUpdate = fetchedAt
  }

  private func report(_ error: Error) {
    log("tfl request failed", error)
    errorMessage = "Couldn't load live bus data: \(error.localizedDescription)"
  }
}

nonisolated extension Coordinate {
  init(_ coordinate: CLLocationCoordinate2D) {
    self.init(lat: coordinate.latitude, lon: coordinate.longitude)
  }

  var clCoordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }
}

private let maxRouteStopsSpan = 2500.0
private let maxStopLettersSpan = 1200.0
private let stopsRefreshInterval: TimeInterval = 7 * 24 * 60 * 60
private let arrivalsRefreshInterval: TimeInterval = 30
private let metersPerDegree = 111_320.0

private func distance(_ stop: BusStop, _ origin: CLLocation) -> Double {
  CLLocation(latitude: stop.coordinate.lat, longitude: stop.coordinate.lon).distance(from: origin)
}

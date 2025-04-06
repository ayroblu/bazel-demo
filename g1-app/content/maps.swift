import Foundation
import Log
import MapKit
import maps
import utils

let padding = 0.002
extension ConnectionManager {
  func sendNavigate(route: MKRoute) {
    currentTask = Task {
      do {
        try await sendNavigateInner(route: route)
      } catch {
        log(error)
        let data = G1Cmd.Navigate.endData()
        manager.transmitBoth(data)
      }
    }
  }
  func stopNavigate() {
    currentTask?.cancel()
  }

  func sendNavigateInner(route: MKRoute) async throws {
    let secondaryBounds = routeBounds(route: route)
    let roads = try await fetchRoads(bounds: secondaryBounds)

    log("starting navigate")

    manager.transmitBoth(G1Cmd.Navigate.initData())
    try await Task.sleep(for: .milliseconds(8))

    var prevLocation: (lat: Double, lng: Double)?
    for _ in 1..<1000 {
      let location = try await getUserLocation()
      let lat = location.coordinate.latitude
      let lng = location.coordinate.longitude
      if isSignificantlyDifferent(loc: (lat, lng), prevLoc: prevLocation) {
        try await sendRoadMap(loc: location, route: route, roads: roads)
        log("sent road map")
      } else {
        let data = G1Cmd.Navigate.pollerData()
        manager.transmitBoth(data)
        log("sent poll")
      }
      try await Task.sleep(for: .seconds(1))
      prevLocation = (lat, lng)
    }
    let data = G1Cmd.Navigate.endData()
    manager.transmitBoth(data)
    log("ending navigate")
  }

  func sendRoadMap(loc: CLLocation, route: MKRoute, roads: OverpassResult)
    async throws
  {
    let lat = loc.coordinate.latitude
    let lng = loc.coordinate.longitude

    let progress = calculateRouteProgress(route: route, currentLocation: loc)
    guard let step = progress.currentStep else { return }
    guard let remainingStepDistance = progress.remainingStepDistance else { return }

    let bounds = ElementBounds(
      minlat: lat - padding, minlng: lng - padding,
      maxlat: lat + padding, maxlng: lng + padding)
    let secondaryBounds = routeBounds(route: route)
    let pos = getPosInBoundsClamped(dim: (488, 136), pos: (lat, lng), bounds: secondaryBounds)

    let directionsData = G1Cmd.Navigate.directionsData(
      totalDuration: progress.remainingDuration.prettyPrint(),
      totalDistance: "\(Int(progress.remainingDistance))m",
      direction: step.instructions,
      distance: "\(Int(remainingStepDistance))m", speed: "0km/h",
      x: pos.x.bytes(byteCount: 2), y: UInt8(pos.y))
    manager.transmitBoth(directionsData)
    try await Task.sleep(for: .milliseconds(8))

    let roadMap = roads.renderMap(bounds: bounds, dim: (136, 136))
    let selfMap = getSelfMap(
      dim: (136, 136), route: route, bounds: bounds,
      selfArrow: SelfArrow(lat: lat, lng: lng))

    let primaryImageData = G1Cmd.Navigate.primaryImageData(image: roadMap, overlay: selfMap)
    for data in primaryImageData {
      manager.transmitBoth(data)
      try await Task.sleep(for: .milliseconds(8))
    }

    let secondaryRoadMap = roads.renderMap(bounds: secondaryBounds, dim: (488, 136))
    let secondarySelfMap = getSelfMap(
      dim: (488, 136), route: route, bounds: secondaryBounds)

    let secondaryImageData = G1Cmd.Navigate.secondaryImageData(
      image: secondaryRoadMap, overlay: secondarySelfMap)
    for data in secondaryImageData {
      manager.transmitBoth(data)
      try await Task.sleep(for: .milliseconds(8))
    }

  }
}

private func isSignificantlyDifferent(
  loc: (lat: Double, lng: Double), prevLoc: (lat: Double, lng: Double)?
) -> Bool {
  if let prevLoc {
    return calculateDistance(lat1: loc.lat, lon1: loc.lng, lat2: prevLoc.lat, lon2: prevLoc.lng)
      > 10
  } else {
    return true
  }
}

func calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
  // in meters
  let earthRadius = 6371000.0

  let lat1Rad = lat1 * .pi / 180
  let lon1Rad = lon1 * .pi / 180
  let lat2Rad = lat2 * .pi / 180
  let lon2Rad = lon2 * .pi / 180

  let deltaLat = lat2Rad - lat1Rad
  let deltaLon = lon2Rad - lon1Rad

  let a =
    sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1Rad) * cos(lat2Rad) * sin(deltaLon / 2)
    * sin(deltaLon / 2)

  let c = 2 * atan2(sqrt(a), sqrt(1 - a))

  let distance = earthRadius * c

  return distance
}

private func routeBounds(route: MKRoute) -> ElementBounds {
  let rect = route.toElementBounds()
  log("rect", rect)
  let isWidth = rect.width / 488 * 136 > rect.height
  let baseSize = isWidth ? rect.width / 488 : rect.height / 136
  let size = baseSize * 1.1
  let paddingY = size * 68
  let paddingX = size * 244
  let (lat, lng) = rect.center
  return ElementBounds(
    minlat: lat - paddingY, minlng: lng - paddingX,
    maxlat: lat + paddingY, maxlng: lng + paddingX)
}

extension MKRoute {
  func toElementBounds() -> ElementBounds {
    let boundingRect = self.polyline.boundingMapRect
    let region = MKCoordinateRegion(boundingRect)
    let center = region.center
    let span = region.span
    let minlat = center.latitude - (span.latitudeDelta / 2.0)
    let maxlat = center.latitude + (span.latitudeDelta / 2.0)
    let minlng = center.longitude - (span.longitudeDelta / 2.0)
    let maxlng = center.longitude + (span.longitudeDelta / 2.0)

    return ElementBounds(minlat: minlat, minlng: minlng, maxlat: maxlat, maxlng: maxlng)
  }
}
struct LocSearchResult: Identifiable {
  let id: MKMapItem.Identifier
  let item: MKMapItem
  let route: MKRoute
  let title: String
  let subtitle: String

  static func from(item: MKMapItem, route: MKRoute) -> LocSearchResult? {
    guard let id = item.identifier else {
      print("no identifier")
      return nil
    }
    guard let title = item.name else {
      print("no title")
      return nil
    }
    let thoroughfare = item.placemark.thoroughfare
    let subThoroughfare = item.placemark.subThoroughfare
    let distance = route.distance
    let expectedTravelTime = route.expectedTravelTime
    let subtitle = [
      prettyPrintDistance(distance), expectedTravelTime.prettyPrintMinutes(), subThoroughfare,
      thoroughfare,
    ]
    .compactMap { $0 }.joined(separator: " ")
    return LocSearchResult(id: id, item: item, route: route, title: title, subtitle: subtitle)
  }
}
private func prettyPrintDistance(_ distance: Double) -> String {
  if distance > 1000 {
    return String(format: "%.1fkm", distance / 1000.0)
  } else {
    return String(format: "%dm", Int(distance))
  }
}
func getSearchResults(textQuery: String) async -> [LocSearchResult] {
  let locations = await searchLocations(textQuery: textQuery)
  let here = MKMapItem.forCurrentLocation()
  return await asyncAll(
    locations.map { location in
      return { () -> LocSearchResult? in
        guard let route = await getDirections(from: here, to: location) else { return nil }
        return LocSearchResult.from(item: location, route: route)
      }
    }
  ).compactMap { $0 }
}
func searchLocations(textQuery: String) async -> [MKMapItem] {
  guard let userLocation = try? await getUserLocation() else { return [] }
  let searchRequest = MKLocalSearch.Request()
  searchRequest.naturalLanguageQuery = textQuery
  let region = MKCoordinateRegion(
    center: userLocation.coordinate,
    latitudinalMeters: 3000,
    longitudinalMeters: 3000
  )
  searchRequest.region = region
  searchRequest.resultTypes = .pointOfInterest
  searchRequest.regionPriority = .required

  let search = MKLocalSearch(request: searchRequest)
  let response = try? await search.start()
  if let response {
    return response.mapItems
  } else {
    log("failed to do search")
    return []
  }
}
func getDirections(textQuery: String) async -> MKRoute? {
  let searchRequest = MKLocalSearch.Request()
  searchRequest.naturalLanguageQuery = textQuery
  let search = MKLocalSearch(request: searchRequest)
  let response = try? await search.start()
  guard let to = response?.mapItems.first else { return nil }
  let from = MKMapItem.forCurrentLocation()
  return await getDirections(from: from, to: to)
}
func getDirections(from: MKMapItem, to: MKMapItem) async -> MKRoute? {
  // Create and configure the request
  let request = MKDirections.Request()
  request.source = from
  request.destination = to
  request.transportType = .walking
  request.requestsAlternateRoutes = true
  // request.transportType = .cycling
  // request.transportType = .transit
  // request.transportType = .automobile

  // Get the directions based on the request
  let directions = MKDirections(request: request)
  let response = try? await directions.calculate()
  // print(response?.routes.first?.steps.map { $0.instructions } ?? [])
  // print(response?.routes.first?.steps.map { $0.distance } ?? [])
  // print(response?.routes.first?.steps.map { $0.notice } ?? [])
  // print(
  //   response?.routes.first?.steps.map {
  //     switch $0.transportType {
  //     case .walking: "walking"
  //     case .automobile: "car"
  //     case .transit: "train"
  //     case _: "unknown"
  //     }
  //   } ?? [])
  return response?.routes.first
}
func getMKMapItem(lat: Double, lng: Double) -> MKMapItem {
  let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
  let placemark = MKPlacemark(coordinate: coordinate)
  let mapItem = MKMapItem(placemark: placemark)
  return mapItem
}

extension TimeInterval {
  func prettyPrint() -> String {
    let totalSeconds = Int(self)
    let hours = totalSeconds / 3600
    let minutes = Int(ceil(Double(totalSeconds) / 60.0))

    if hours > 0 {
      return String(format: "%d hours %d mins", hours, minutes)
    } else {
      return String(format: "%d mins", minutes)
    }
  }
  func prettyPrintMinutes() -> String {
    let totalSeconds = Int(self)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d hours %d mins", hours, minutes)
    } else if minutes > 0 {
      return String(format: "%d mins", minutes)
    } else {
      return String(format: "%d secs", seconds)
    }
  }
}

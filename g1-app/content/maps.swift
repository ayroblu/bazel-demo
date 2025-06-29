import Foundation
import Log
import LogUtils
import MapKit
import g1protocol
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
        let data = Device.Navigate.endData()
        bluetoothManager.transmitBoth(data)
      }
    }
  }
  func stopNavigate() {
    currentTask?.cancel()
  }

  func sendNavigateInner(route: MKRoute) async throws {
    let secondaryBounds = routeBounds(route: route)

    log("starting navigate")

    bluetoothManager.transmitBoth(Device.Navigate.initData())
    try await Task.sleep(for: .milliseconds(8))

    var prevLocation: (lat: Double, lng: Double)?
    for i in 1..<1000 {
      let location = try await getUserLocation()
      let lat = location.coordinate.latitude
      let lng = location.coordinate.longitude
      if isSignificantlyDifferent(loc: (lat, lng), prevLoc: prevLocation) || i % 5 == 0 {
        let roads = try await fetchRoads(bounds: secondaryBounds)
        if let done = try await sendRoadMap(loc: location, route: route, roads: roads), done {
          break
        }
        log("sent road map", i)
        prevLocation = (lat, lng)
      } else {
        let data = Device.Navigate.pollerData()
        bluetoothManager.transmitBoth(data)
        log("sent poll", i)
      }
      try await Task.sleep(for: .seconds(1))
    }
    let data = Device.Navigate.endData()
    bluetoothManager.transmitBoth(data)
    log("ending navigate")
  }

  func sendRoadMap(loc: CLLocation, route: MKRoute, roads: OverpassResult)
    async throws -> Bool?
  {
    let lat = loc.coordinate.latitude
    let lng = loc.coordinate.longitude

    let progress = calculateRouteProgress(route: route, currentLocation: loc)
    if progress.remainingDistance < 10 {
      return true
    }
    guard let step = progress.currentStep else { return nil }
    guard let remainingStepDistance = progress.remainingStepDistance else { return nil }

    let bounds = ElementBounds(
      minlat: lat - padding, minlng: lng - padding,
      maxlat: lat + padding, maxlng: lng + padding)
    let secondaryBounds = routeBounds(route: route)
    let pos = getPosInBoundsClamped(dim: (488, 136), pos: (lat, lng), bounds: secondaryBounds)

    let directionsData = Device.Navigate.directionsData(
      totalDuration: progress.remainingDuration.prettyPrint(),
      totalDistance: "\(Int(progress.remainingDistance))m",
      direction: step.instructions,
      distance: "\(Int(remainingStepDistance))m", speed: getPrettySpeed(),
      x: pos.x.bytes(byteCount: 2), y: UInt8(pos.y))
    bluetoothManager.transmitBoth(directionsData)
    try await Task.sleep(for: .milliseconds(8))

    let roadMap = roads.renderMap(bounds: bounds, dim: (136, 136))
    let selfMap = getSelfMap(
      dim: (136, 136), route: route, bounds: bounds,
      history: LocationManager.shared.locationHistory.toTuple(),
      // -getAngle: bearing is clockwise, but rotations are counter clockwise
      selfArrow: SelfArrow(lat: lat, lng: lng, angle: getSpeed() > 1 ? -getAngle() : nil),
    )

    let primaryImageData = Device.Navigate.primaryImageData(image: roadMap, overlay: selfMap)
    for data in primaryImageData {
      bluetoothManager.transmitBoth(data)
      try await Task.sleep(for: .milliseconds(8))
    }

    let secondaryRoadMap = roads.renderMap(bounds: secondaryBounds, dim: (488, 136))
    let secondarySelfMap = getSelfMap(
      dim: (488, 136), route: route, bounds: secondaryBounds,
      history: LocationManager.shared.locationHistory.toTuple())

    let secondaryImageData = Device.Navigate.secondaryImageData(
      image: secondaryRoadMap, overlay: secondarySelfMap)
    for data in secondaryImageData {
      bluetoothManager.transmitBoth(data)
      try await Task.sleep(for: .milliseconds(8))
    }

    return nil
  }
}
enum NavigationError: Error {
  case arrived
}

private func isSignificantlyDifferent(
  loc: (lat: Double, lng: Double), prevLoc: (lat: Double, lng: Double)?
) -> Bool {
  if let prevLoc {
    return CLLocation(latitude: loc.lat, longitude: loc.lng).distance(
      from: CLLocation(latitude: prevLoc.lat, longitude: prevLoc.lng)) < 10
  } else {
    return true
  }
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
struct MyMapItem {
  let lat: Double
  let lng: Double
  let thoroughfare: String?
  let subThoroughfare: String?
}
struct LocSearchResult: Identifiable, Equatable {
  let id: String
  let route: MKRoute
  let title: String
  let subtitle: String

  // Just for persistence purposes
  var mapItem: MyMapItem? = nil

  static func from(item: MKMapItem, route: MKRoute) -> LocSearchResult? {
    let id = item.identifier?.rawValue ?? UUID().uuidString
    let title = item.name ?? "<unknown>"
    let thoroughfare = item.placemark.thoroughfare
    let subThoroughfare = item.placemark.subThoroughfare
    let distance = route.distance
    let expectedTravelTime = route.expectedTravelTime
    let subtitle = [
      prettyPrintDistance(distance), expectedTravelTime.prettyPrintMinutes(), subThoroughfare,
      thoroughfare,
    ]
    .compactMap { $0 }.joined(separator: " ")
    let mapItem = MyMapItem(
      lat: item.placemark.coordinate.latitude, lng: item.placemark.coordinate.longitude,
      thoroughfare: thoroughfare, subThoroughfare: subThoroughfare)
    return LocSearchResult(id: id, route: route, title: title, subtitle: subtitle, mapItem: mapItem)
  }

  public static func == (lhs: LocSearchResult, rhs: LocSearchResult) -> Bool {
    return lhs.id == rhs.id
  }
}
func prettyPrintDistance(_ distance: Double) -> String {
  if distance > 1000 {
    return String(format: "%.1fkm", distance / 1000.0)
  } else {
    return String(format: "%dm", Int(distance))
  }
}
func getSearchResults(
  textQuery: String, transportType: MKDirectionsTransportType
) async -> [LocSearchResult] {
  let locations = await searchLocations(textQuery: textQuery)
  let here = MKMapItem.forCurrentLocation()
  log("num search locations", locations.count)
  return await asyncAll(
    locations.map { location in
      return { () -> LocSearchResult? in
        let route = await tryFn {
          try await getDirections(
            from: here, to: location,
            transportType: transportType)
        }
        guard let route else { return nil }
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
  searchRequest.resultTypes = [.pointOfInterest, .address]
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
func getDirections(
  textQuery: String, transportType: MKDirectionsTransportType
) async throws -> MKRoute? {
  let searchRequest = MKLocalSearch.Request()
  searchRequest.naturalLanguageQuery = textQuery
  let search = MKLocalSearch(request: searchRequest)
  let response = try await search.start()
  guard let to = response.mapItems.first else { return nil }
  let from = MKMapItem.forCurrentLocation()
  return try await getDirections(from: from, to: to, transportType: transportType)
}
func getDirections(
  from: MKMapItem, to: MKMapItem,
  transportType: MKDirectionsTransportType
) async throws -> MKRoute? {
  let request = MKDirections.Request()
  request.source = from
  request.destination = to
  request.transportType = transportType
  // request.requestsAlternateRoutes = true

  let directions = MKDirections(request: request)
  let response = try await directions.calculate()
  return response.routes.first
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
extension LocationHistory {
  func prettySpeed() -> String {
    let metersPerSecond = getSpeed()
    let kmph = Int(metersPerSecond * 3.6)
    return "\(kmph)km/h"
  }
}
func getPrettySpeed() -> String {
  return LocationManager.shared.locationHistory.prettySpeed()
}
func getSpeed() -> Double {
  return LocationManager.shared.locationHistory.getSpeed()
}
func getAngle() -> Double {
  return LocationManager.shared.locationHistory.getAngle()
}

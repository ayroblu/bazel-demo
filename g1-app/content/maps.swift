import Foundation
import Log
import MapKit
import maps
import utils

let padding = 0.002
extension ConnectionManager {
  func sendRoadMap(lat: Double, lng: Double, route: MKRoute) async throws {
    let secondaryBounds = routeBounds(route: route)
    let roads = try await fetchRoads(bounds: secondaryBounds)

    let pos = getPosInBounds(dim: (488, 136), pos: (lat, lng), bounds: secondaryBounds)
    guard pos.x >= 0 && pos.x < 488 && pos.y >= 0 && pos.y < 136 else {
      log("pos was outside bounds", pos)
      return
    }

    manager.transmitBoth(G1Cmd.Navigate.initData())
    try? await Task.sleep(for: .milliseconds(8))

    // TODO: pos x and y may not be a byte
    let bounds = ElementBounds(
      minlat: lat - padding, minlng: lng - padding,
      maxlat: lat + padding, maxlng: lng + padding)
    let directionsData = G1Cmd.Navigate.directionsData(
      totalDuration: route.expectedTravelTime.prettyPrint(),
      totalDistance: "\(Int(route.distance))m",
      direction: route.steps[0].instructions,
      distance: "\(Int(route.steps[0].distance))m", speed: "0km/h",
      x: pos.x.bytes(byteCount: 2), y: UInt8(pos.y))
    manager.transmitBoth(directionsData)
    try? await Task.sleep(for: .milliseconds(8))

    let roadMap = roads.renderMap(bounds: bounds, dim: (136, 136))
    let selfMap = getSelfMap(
      dim: (136, 136), route: route, bounds: bounds,
      selfArrow: SelfArrow(lat: lat, lng: lng))
    let primaryImageData = G1Cmd.Navigate.primaryImageData(image: roadMap, overlay: selfMap)
    for data in primaryImageData {
      manager.transmitBoth(data)
      try? await Task.sleep(for: .milliseconds(8))
    }

    let secondaryRoadMap = roads.renderMap(bounds: secondaryBounds, dim: (488, 136))
    let secondarySelfMap = getSelfMap(
      dim: (488, 136), route: route, bounds: secondaryBounds)
    let secondaryImageData = G1Cmd.Navigate.secondaryImageData(
      image: secondaryRoadMap, overlay: secondarySelfMap)
    for data in secondaryImageData {
      manager.transmitBoth(data)
      try? await Task.sleep(for: .milliseconds(8))
    }

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
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%dh %dm %ds", hours, minutes, seconds)
    } else if minutes > 0 {
      return String(format: "%dm %ds", minutes, seconds)
    } else {
      return String(format: "%ds", seconds)
    }
  }
  func prettyPrintMinutes() -> String {
    let totalSeconds = Int(self)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%dh %dm", hours, minutes)
    } else if minutes > 0 {
      return String(format: "%dm", minutes)
    } else {
      return String(format: "%ds", seconds)
    }
  }
}

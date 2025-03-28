import Foundation
import Log
import MapKit
import maps

let padding = 0.001
extension ConnectionManager {
  func sendRoadMap(lat: Double, lng: Double, route: MKRoute) async throws {
    let secondaryBounds = routeBounds(route: route)
    let bounds = ElementBounds(
      minlat: lat - padding, minlng: lng - padding,
      maxlat: lat + padding, maxlng: lng + padding)
    let roads = try await fetchRoads(bounds: secondaryBounds)
    let roadMap = roads.renderMap(bounds: bounds, dim: (136, 136))
    let selfMap = getSelfMap(width: 136, height: 136, angle: 0)
    let primaryImageData = G1Cmd.Navigate.primaryImageData(image: roadMap, overlay: selfMap)
    for data in primaryImageData {
      manager.transmitBoth(data)
      try? await Task.sleep(for: .milliseconds(8))
    }

    let secondaryRoadMap = roads.renderMap(bounds: secondaryBounds, dim: (488, 136))
    let secondarySelfMap = getSelfMap(width: 488, height: 136, angle: 0)
    let secondaryImageData = G1Cmd.Navigate.secondaryImageData(
      image: secondaryRoadMap, overlay: secondarySelfMap)
    for data in secondaryImageData {
      manager.transmitBoth(data)
      try? await Task.sleep(for: .milliseconds(8))
    }
  }
  // Overlay: MapBoard + arrow for direction
  // history: dashed, route: solid
}

// func fetchRoadMapWithFallback(bounds: ElementBounds, width: Int, height: Int) async -> [Bool] {
//   do {
//     return try await fetchRoadMap(bounds: bounds, width: width, height: height)
//   } catch {
//     log("sendRoadMap", error)
//     return G1Cmd.Navigate.parseExampleImage(image: exampleImage1)
//   }
// }

private func routeBounds(route: MKRoute) -> ElementBounds {
  let rect = route.toElementBounds()
  log("rect", rect)
  let isWidth = rect.width / 488 * 136 > rect.height
  let size = isWidth ? rect.width / 488 : rect.height / 136
  let paddingY = size * 68 + 0.001
  let paddingX = size * 244 + 0.001
  let (lat, lng) = rect.center
  log(rect.center, paddingX, paddingY)
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

func getDirections() async -> MKRoute? {
  let searchRequest = MKLocalSearch.Request()
  searchRequest.naturalLanguageQuery = "Sainsburys"
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

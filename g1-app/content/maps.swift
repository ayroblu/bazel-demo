import Foundation
import Log
import maps

let padding = 0.001
let longerPadding = padding * 488 / 136
extension ConnectionManager {
  func sendRoadMap(lat: Double, lng: Double) async {
    let bounds = ElementBounds(
      minlat: lat - padding, minlng: lng - padding,
      maxlat: lat + padding, maxlng: lng + padding)
    let roadMap = await fetchRoadMapWithFallback(bounds: bounds, width: 136, height: 136)
    let primaryImageData = G1Cmd.Navigate.primaryImageData(
      image: roadMap,
      overlay: G1Cmd.Navigate.parseExampleImage(image: exampleImage1Overlay))
    for data in primaryImageData {
      manager.transmitBoth(data)
      try? await Task.sleep(for: .milliseconds(8))
    }

    let secondaryBounds = ElementBounds(
      minlat: lat - padding, minlng: lng - longerPadding,
      maxlat: lat + padding, maxlng: lng + longerPadding)
    let secondaryRoadMap = await fetchRoadMapWithFallback(
      bounds: secondaryBounds, width: 488, height: 136)
    let secondaryImageData = G1Cmd.Navigate.secondaryImageData(
      image: secondaryRoadMap,
      overlay: G1Cmd.Navigate.parseExampleImage(image: exampleImage2Overlay))
    for data in secondaryImageData {
      manager.transmitBoth(data)
      try? await Task.sleep(for: .milliseconds(8))
    }
  }
}

func fetchRoadMapWithFallback(bounds: ElementBounds, width: Int, height: Int) async -> [Bool] {
  do {
    return try await fetchRoadMap(bounds: bounds, width: width, height: height)
  } catch {
    log("sendRoadMap", error)
    return G1Cmd.Navigate.parseExampleImage(image: exampleImage1)
  }
}

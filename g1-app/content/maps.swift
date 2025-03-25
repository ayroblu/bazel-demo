import Foundation
import maps

extension ConnectionManager {
  func sendRoadMap(minlat: Double, minlng: Double, maxlat: Double, maxlng: Double) async {
    let bounds = ElementBounds(minlat: minlat, minlng: minlng, maxlat: maxlat, maxlng: maxlng)
    let roadMap = await fetchRoadMap(bounds: bounds, width: 135, height: 135)
    let newImageData = G1Cmd.Navigate.primaryImageData(
      image: roadMap,
      overlay: G1Cmd.Navigate.parseExampleImage(image: exampleImage1Overlay))
    for data in newImageData {
      manager.transmitBoth(data)
      try? await Task.sleep(for: .milliseconds(8))
    }
  }
}

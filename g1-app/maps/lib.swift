import Foundation

public func fetchRoadMap(bounds: ElementBounds, width: Int, height: Int) async -> [Bool] {
  let arr: [Bool] = Array(repeating: false, count: width * height)
  let roads = await fetchRoads(bounds: bounds)
  return arr
}

import Foundation

let padding = 0.001
public func fetchRoadMap(bounds: ElementBounds, width: Int, height: Int) async throws -> [Bool] {
  let dlat = bounds.maxlat - bounds.minlat
  let dlng = bounds.maxlng - bounds.minlng
  let paddingWidth = Int(ceil(padding / dlng * Double(width)))
  let paddingHeight = Int(ceil(padding / dlat * Double(height)))
  let largerWidth = width + paddingWidth * 2
  let largerHeight = height + paddingHeight * 2
  let largerBounds = ElementBounds(
    minlat: bounds.minlat - padding, minlng: bounds.minlng - padding,
    maxlat: bounds.maxlat + padding, maxlng: bounds.maxlng + padding)

  let roads = try await fetchRoads(bounds: largerBounds)
  var mapBoard = MapBoard(width: largerWidth, height: largerHeight)
  mapBoard.render(data: roads, bounds: largerBounds)
  mapBoard.crop(start: (paddingWidth, paddingHeight), dim: (width, height))

  return mapBoard.board.flatMap { $0 }
}

struct MapBoard {
  var width: Int
  var height: Int
  var board: [[Bool]]

  init(width: Int, height: Int) {
    self.board = Array(repeating: Array(repeating: false, count: width), count: height)
    self.width = width
    self.height = height
  }
}

public struct ElementBounds: Codable {
  public let minlat: Double
  public let minlng: Double
  public let maxlat: Double
  public let maxlng: Double

  public init(minlat: Double, minlng: Double, maxlat: Double, maxlng: Double) {
    self.minlat = minlat
    self.minlng = minlng
    self.maxlat = maxlat
    self.maxlng = maxlng
  }
}

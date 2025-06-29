import Foundation
import MapKit
import utils

extension OverpassResult {
  public func renderMap(bounds: ElementBounds, dim: (width: Int, height: Int)) -> [Bool] {
    let (width, height) = dim
    var mapBoard = MapBoard(width: width, height: height)
    mapBoard.render(data: self, bounds: bounds)
    return mapBoard.board.flatMap { $0 }
  }
}

public func getSelfMap(
  dim: (width: Int, height: Int), route: MKRoute, bounds: ElementBounds, history: [((Double, Double), (Double, Double))], selfArrow: SelfArrow? = nil
) -> [Bool] {
  let (width, height) = dim
  var board = MapBoard(width: width, height: height)
  if let selfArrow {
    let (x, y) = getPosInBounds(
      dim: (width, height), pos: (selfArrow.lat, selfArrow.lng), bounds: bounds)
    if let angle = selfArrow.angle {
      board.merge(getArrowBoard(angle: angle), pos: (x - 8, y - 8))
    } else {
      board.drawCircleOutline(pos: (x, y), radius: 8)
    }
  }
  board.renderRoute(route: route, bounds: bounds)
  board.renderDashedPath(path: history, bounds: bounds)
  return board.board.flatMap { $0 }
}

public func getPosInBounds(
  dim: (width: Int, height: Int), pos: (lat: Double, lng: Double), bounds: ElementBounds
) -> (x: Int, y: Int) {
  let (width, height) = dim
  let (lat, lng) = pos
  let x = Int((lng - bounds.minlng) / (bounds.maxlng - bounds.minlng) * Double(width))
  let y = Int((bounds.maxlat - lat) / (bounds.maxlat - bounds.minlat) * Double(height))
  return (x, y)
}
public func getPosInBoundsClamped(
  dim: (width: Int, height: Int), pos: (lat: Double, lng: Double), bounds: ElementBounds
) -> (x: Int, y: Int) {
  let (width, height) = dim
  let (x, y) = getPosInBounds(dim: dim, pos: pos, bounds: bounds)
  return (x.clamped(to: 0...width), y.clamped(to: 0...height))
}

public struct SelfArrow {
  public let lat: Double
  public let lng: Double
  public let angle: Double?
  public init(lat: Double, lng: Double, angle: Double?) {
    self.lat = lat
    self.lng = lng
    self.angle = angle
  }
}

private func getArrowBoard(angle: Double) -> MapBoard {
  var arrowBoard = MapBoard(width: 16, height: 16)
  arrowBoard.drawArrow(position: (0, 4), dim: (16, 8), lineWidth: 4)
  arrowBoard.rotate(angle: angle)
  return arrowBoard
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

extension ElementBounds {
  public var center: (lat: Double, lng: Double) {
    return (lat: (maxlat + minlat) / 2, lng: (maxlng + minlng) / 2)
  }
  public var width: Double {
    return (maxlng - minlng)
  }
  public var height: Double {
    return (maxlat - minlat)
  }
}

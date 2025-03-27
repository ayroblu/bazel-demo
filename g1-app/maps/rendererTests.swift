import MySnapshotTesting
import XCTest

@testable import maps

class RendererTests: XCTestCase {
  func testRenderRoads() throws {
    let bounds = ElementBounds(minlat: 51.510, minlng: -0.137, maxlat: 51.512, maxlng: -0.135)
    var mapBoard = MapBoard(width: 136, height: 136)

    let roads = try loadJson(filename: "roads.json", jsonType: OverpassResult.self)
    mapBoard.render(data: roads, bounds: bounds)
    let board = mapBoard.board.toBoardString()
    assertSnapshot(of: board, as: .lines, record: true)
  }

  func loadJson<T: Decodable>(filename: String, jsonType: T.Type) throws -> T {
    let fixturesDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FIXTURES"]!)
    let fileURL = fixturesDir.appendingPathComponent(filename)
    let data = try Data(contentsOf: fileURL)
    let decoder = JSONDecoder()
    let roads = try decoder.decode(jsonType, from: data)

    return roads
  }
}

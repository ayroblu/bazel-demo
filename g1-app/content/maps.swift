import Foundation

extension ConnectionManager {
  func sendRoadMap(bounds: ElementBounds) async {
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

func rasterLine(
  _ a: (Double, Double), _ b: (Double, Double), width: Int, board: inout [Bool], _ dims: (Int, Int)
) {
  let (ax, ay) = a
  let (bx, by) = b
  let lenX = abs(bx - ax)
  let lenY = abs(by - ay)
  let isVertical = lenY > lenX
  // round ax, ay, set board[x][y] = true
  let dir =
    isVertical
    ? ay > by ? (((bx - ax) / lenY), -1) : (((bx - ax) / lenY), 1)
    : ax > bx ? (-1, ((by - ay) / lenX)) : (1, ((by - ay) / lenX))
  func rangeWidth(_ v: Double) -> Range<Int> {
    let upper = Int(round(v)) + (width - 1) / 2
    let lower = upper - width
    return lower..<upper
  }

  // board[round(x + dirX)][round(y + dirY)] = true
  // var counter = width
  if isVertical {
    // for _ in ay..<by {
    let x = ax
    let y = ay
    for dx in rangeWidth(x) {
      // board[x + dx][y] = true
      rasterPoint(x + Double(dx), y, board: &board, dims)
    }
    // }
  }
}
func rasterPoint(_ x: Double, _ y: Double, board: inout [Bool], _ dims: (Int, Int)) {
  board[Int(round(x)) + Int(round(y)) * dims.1] = true
}

private func fetchRoadMap(bounds: ElementBounds, width: Int, height: Int) async -> [Bool] {
  let arr: [Bool] = Array(repeating: false, count: width * height)
  let roads = await fetchRoads(bounds: bounds)
  return arr
}

private func fetchRoads(bounds: ElementBounds) async -> OverpassResult? {
  return await fetchPost(
    OverpassResult.self,
    urlPath: "https://overpass-api.de/api/interpreter",
    body: "data=[out:json];way[\"highway\"](51.511,-0.136,51.512,-0.135);out geom;")
}

struct ElementBounds: Codable {
  let minlat: Double
  let minlon: Double
  let maxlat: Double
  let maxlon: Double
}
struct LatLng: Codable {
  let lat: Double
  let lng: Double
}
struct OverpassTags: Codable {
  let highway: String?  // unclassified
  let lit: String?  // yes
  let maxspeed: String?  // 20 mph
  // let maxspeed:type: String? // GB:zone20
  let name: String?
  let oneway: String?  // yes
  // let sidewalk:both: String? // separate
  let source: String?  // survey
  let surface: String?  // asphalt
}
struct OverpassElement: Codable {
  let type: String
  let id: Int
  let bounds: ElementBounds
  let nodes: [Int]
  let geometry: [LatLng]
  let tags: OverpassTags
}
struct OverpassResult: Codable {
  let version: Double
  let generator: String
  // let osm3s: Osm3s
  let elements: [OverpassElement]
}

func fetchPost<T>(_ type: T.Type, urlPath: String, body: String?) async -> T? where T: Decodable {
  guard let url = URL(string: urlPath) else { return nil }
  var urlRequest = URLRequest(url: url)
  urlRequest.httpMethod = "POST"
  if let body {
    urlRequest.httpBody = body.data()
  }
  guard let (data, _) = try? await URLSession.shared.data(for: urlRequest) else { return nil }
  let decoder = JSONDecoder()
  return try? decoder.decode(type, from: data)
}

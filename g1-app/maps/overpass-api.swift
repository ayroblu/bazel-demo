import Foundation
import Log

public func fetchRoads(bounds: ElementBounds) async throws -> OverpassResult {
  // Also see: https://overpass-turbo.eu
  let body =
    "data=[out:json];way[\"highway\"](\(bounds.minlat),\(bounds.minlng),\(bounds.maxlat),\(bounds.maxlng));out geom;"
  log("fetching from overpass", body)
  let result = try await fetchPost(
    OverpassResult.self,
    urlPath: "https://overpass-api.de/api/interpreter",
    body: body
  )
  log("roads fetched", result.elements.count)
  return result
  // curl -X POST -g "https://overpass-api.de/api/interpreter" \
  //   --data-urlencode "data=[out:json];way[\"highway\"](51.511,-0.136,51.512,-0.135);out geom;" > roads.json
}

struct Bounds: Codable {
  let minlat: Double
  let minlon: Double
  let maxlat: Double
  let maxlon: Double
}
struct LatLng: Codable {
  let lat: Double
  let lon: Double
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
  let bounds: Bounds
  let nodes: [Int]
  let geometry: [LatLng]
  let tags: OverpassTags
}
public struct OverpassResult: Codable {
  let version: Double
  let generator: String
  // let osm3s: Osm3s
  var elements: [OverpassElement]

  public static func empty() -> OverpassResult {
    return OverpassResult(version: 0.0, generator: "", elements: [])
  }
}

func fetchPost<T>(_ type: T.Type, urlPath: String, body: String?) async throws -> T
where T: Decodable {
  guard let url = URL(string: urlPath) else { throw URLError(.badURL) }
  var urlRequest = URLRequest(url: url)
  urlRequest.httpMethod = "POST"
  if let body {
    urlRequest.httpBody = body.data(using: .utf8)
  }
  let (data, _) = try await URLSession.shared.data(for: urlRequest)
  let decoder = JSONDecoder()
  return try decoder.decode(type, from: data)
}

extension Array where Element == OverpassResult {
  public func merge() -> OverpassResult? {
    if self.count <= 1 {
      return self.first
    }
    let first = self.first!
    let elements = self.flatMap { $0.elements }
    return OverpassResult(version: first.version, generator: first.generator, elements: elements)
  }
}


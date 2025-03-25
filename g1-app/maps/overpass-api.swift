import Foundation

func fetchRoads(bounds: ElementBounds) async -> OverpassResult? {
  return await fetchPost(
    OverpassResult.self,
    urlPath: "https://overpass-api.de/api/interpreter",
    body:
      "data=[out:json];way[\"highway\"](\(bounds.minlat),\(bounds.minlng),\(bounds.maxlat),\(bounds.maxlng));out geom;"
  )
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
    urlRequest.httpBody = body.data(using: .utf8)
  }
  guard let (data, _) = try? await URLSession.shared.data(for: urlRequest) else { return nil }
  let decoder = JSONDecoder()
  return try? decoder.decode(type, from: data)
}

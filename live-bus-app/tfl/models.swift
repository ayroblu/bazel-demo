import Foundation

public struct Coordinate: Codable, Hashable, Sendable {
  public let lat: Double
  public let lon: Double

  public init(lat: Double, lon: Double) {
    self.lat = lat
    self.lon = lon
  }
}

public struct BusLine: Decodable, Hashable, Sendable, Identifiable {
  public let id: String
  public let name: String
}

public struct BusStop: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let name: String
  public let letter: String?
  public let towards: String?
  public let coordinate: Coordinate
  public let lineIds: [String]

  var hasRoutes: Bool { !lineIds.isEmpty }
}

public struct Arrival: Hashable, Sendable, Identifiable {
  public let id: String
  public let vehicleId: String
  public let stopId: String
  public let lineId: String
  public let lineName: String
  public let direction: String
  public let destination: String
  public let expectedArrival: Date
}

public struct BusRoute: Hashable, Sendable {
  public let lineId: String
  public let lineName: String
  public let paths: [RoutePath]

  public var stops: [BusStop] {
    var seen = Set<String>()
    return paths.flatMap { $0.stops.map(\.stop) }.filter { seen.insert($0.id).inserted }
  }
}

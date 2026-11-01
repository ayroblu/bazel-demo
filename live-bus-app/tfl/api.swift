import Foundation
import http

public func getBusLines() async throws -> [BusLine] {
  let lines = try await getJson(
    [BusLine].self, urlPath: "\(tflBase)/Line/Mode/bus",
    ttl: Date().addingTimeInterval(7 * 24 * 60 * 60))
  return lines.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

public func getStopsNear(_ coordinate: Coordinate, radius: Int) async throws -> [BusStop] {
  let response = try await getJson(
    StopPointsResponse.self,
    urlPath:
      "\(tflBase)/StopPoint/?lat=\(coordinate.lat)&lon=\(coordinate.lon)&stopTypes=NaptanPublicBusCoachTram&modes=bus&radius=\(radius)"
  )
  return response.stopPoints.map(BusStop.init).filter(\.hasRoutes)
}

public func getStop(id: String) async throws -> BusStop {
  BusStop(try await getJson(RawStop.self, urlPath: "\(tflBase)/StopPoint/\(id)"))
}

public func getStopArrivals(stopId: String) async throws -> [Arrival] {
  try await getArrivals(urlPath: "\(tflBase)/StopPoint/\(stopId)/Arrivals")
}

public func getLineArrivals(lineIds: [String]) async throws -> [Arrival] {
  try await getArrivals(urlPath: "\(tflBase)/Line/\(lineIds.joined(separator: ","))/Arrivals")
}

public func getBusRoute(lineId: String) async throws -> BusRoute {
  let outbound = try await getSequence(lineId: lineId, direction: "outbound")
  let sequences =
    outbound.isOutboundOnly
    ? [outbound] : [outbound, try await getSequence(lineId: lineId, direction: "inbound")]
  return BusRoute(
    lineId: outbound.lineId, lineName: outbound.lineName,
    paths: sequences.flatMap { sequence in
      makeRoutePaths(
        direction: sequence.direction, lineStrings: sequence.lineStrings,
        sequences: sequence.stopPointSequences.map { $0.stopPoint.map(BusStop.init) })
    })
}

func getBusStopPage(_ page: Int) async throws -> (stops: [BusStop], count: Int, total: Int) {
  let response = try await getJson(
    StopPointsResponse.self, urlPath: "\(tflBase)/StopPoint/Mode/bus?page=\(page)", retries: 5)
  return (
    response.stopPoints.filter { $0.stopType == busStopType }.map(BusStop.init).filter(\.hasRoutes),
    response.stopPoints.count, response.total
  )
}

private let tflBase = "https://api.tfl.gov.uk"
private let maxRetries = 3

private func getArrivals(urlPath: String) async throws -> [Arrival] {
  try await getJson([RawArrival].self, urlPath: urlPath, retries: maxRetries)
    .compactMap(Arrival.init)
    .sorted { $0.expectedArrival < $1.expectedArrival }
}

private func getSequence(lineId: String, direction: String) async throws -> RawRouteSequence {
  try await getJson(
    RawRouteSequence.self,
    urlPath: "\(tflBase)/Line/\(lineId)/Route/Sequence/\(direction)", retries: maxRetries,
    ttl: Date().addingTimeInterval(24 * 60 * 60))
}

private let busStopType = "NaptanPublicBusCoachTram"

private struct StopPointsResponse: Decodable {
  let stopPoints: [RawStop]
  let total: Int
}

private struct RawStop: Decodable {
  let naptanId: String?
  let stopType: String?
  let id: String?
  let commonName: String?
  let name: String?
  let stopLetter: String?
  let towards: String?
  let lat: Double
  let lon: Double
  let lines: [RawIdentifier]?
  let additionalProperties: [RawProperty]?
}

private struct RawIdentifier: Decodable {
  let id: String
}

private struct RawProperty: Decodable {
  let key: String
  let value: String
}

private struct RawArrival: Decodable {
  let id: String
  let vehicleId: String
  let naptanId: String
  let lineId: String
  let lineName: String
  let direction: String?
  let destinationName: String?
  let towards: String?
  let expectedArrival: String
}

private struct RawRouteSequence: Decodable {
  let lineId: String
  let lineName: String
  let direction: String
  let isOutboundOnly: Bool
  let lineStrings: [String]
  let stopPointSequences: [RawStopSequence]
}

private struct RawStopSequence: Decodable {
  let stopPoint: [RawStop]
}

extension BusStop {
  fileprivate init(_ raw: RawStop) {
    self.init(
      id: raw.naptanId ?? raw.id ?? "",
      name: (raw.commonName ?? raw.name ?? "").split(separator: " ").joined(separator: " "),
      letter: raw.stopLetter,
      towards: raw.towards
        ?? raw.additionalProperties?.first(where: { $0.key == "Towards" })?.value,
      coordinate: Coordinate(lat: raw.lat, lon: raw.lon),
      lineIds: raw.lines?.map(\.id) ?? [])
  }
}

extension Arrival {
  fileprivate init?(_ raw: RawArrival) {
    guard let expectedArrival = try? Date(raw.expectedArrival, strategy: .iso8601) else {
      return nil
    }
    self.init(
      id: raw.id, vehicleId: raw.vehicleId, stopId: raw.naptanId,
      lineId: raw.lineId, lineName: raw.lineName, direction: raw.direction ?? "outbound",
      destination: raw.destinationName ?? raw.towards ?? "",
      expectedArrival: expectedArrival)
  }
}

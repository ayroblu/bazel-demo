import FileUtils
import Foundation

public struct CachedStops: Codable, Sendable {
  public let fetchedAt: Date
  public let stops: [BusStop]
}

@concurrent
public func loadCachedStops() async -> CachedStops? {
  guard let data = try? Data(contentsOf: stopsCacheURL) else { return nil }
  guard let cached = try? JSONDecoder().decode(CachedStops.self, from: data) else { return nil }
  return CachedStops(fetchedAt: cached.fetchedAt, stops: cached.stops.filter(\.hasRoutes))
}

@concurrent
public func downloadAllStops() async throws -> CachedStops {
  var stops: [BusStop] = []
  var fetched = 0
  var total = 1
  var page = 1
  while fetched < total {
    let result = try await getBusStopPage(page)
    guard result.count > 0 else {
      throw StopDownloadError.incomplete(fetched: fetched, total: result.total)
    }
    stops += result.stops
    fetched += result.count
    total = result.total
    page += 1
    if fetched < total {
      try await Task.sleep(for: .seconds(stopPageInterval))
    }
  }
  let cached = CachedStops(fetchedAt: Date(), stops: stops)
  try mkdirp(stopsCacheURL.deletingLastPathComponent())
  try JSONEncoder().encode(cached).write(to: stopsCacheURL, options: .atomic)
  return cached
}

enum StopDownloadError: Error {
  case incomplete(fetched: Int, total: Int)
}

private let stopPageInterval: TimeInterval = 4

private let stopsCacheURL =
  FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0] / "bus-stops.json"

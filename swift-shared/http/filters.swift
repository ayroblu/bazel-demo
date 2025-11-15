import ConcurrentUtils
import Log

struct ETagFilter: HttpFilter {
  func handler(request: HttpRequest, service: (HttpRequest) async throws -> HttpResponse)
    async rethrows -> HttpResponse
  {
    if request.method == .GET && request.options.contains(.nonHydratingEtag) {
      var request = request
      if let storedEtag = getEtag(urlPath: request.path) {
        request.headers["If-None-Match"] = storedEtag
      }
      let result = try await service(request)
      if let etag = result.headers["Etag"], !etag.isEmpty {
        setEtag(urlPath: request.path, etag: etag)
      }
      return result
    } else {
      return try await service(request)
    }
  }
}

struct LoggingFilter: HttpFilter {
  func handler(request: HttpRequest, service: (HttpRequest) async throws -> HttpResponse)
    async rethrows -> HttpResponse
  {
    if !request.options.contains(.skipLog) {
      log("\(request.method) \(request.path)")
    }
    let result = try await service(request)
    if !request.options.contains(.skipLog) {
      log("\(request.method) \(request.path): HTTP-\(result.statusCode)")
    }
    return result
  }
}

struct RetryFilter: HttpFilter {
  func handler(request: HttpRequest, service: (HttpRequest) async throws -> HttpResponse)
    async throws -> HttpResponse
  {
    for _ in 0..<request.retries {
      let result = try? await service(request)
      if result == nil || result?.statusCode == 429 || result?.statusCode == 504 {
        try await Task.sleep(for: .seconds(1))
        continue
      }
      if let result {
        return result
      }
    }
    return try await service(request)
  }
}

final class SingleGetFilter: HttpFilter {
  let cache = SyncDict<HttpRequest, Task<HttpResponse, Error>>()

  func handler(
    request: HttpRequest, service: @escaping @Sendable (HttpRequest) async throws -> HttpResponse
  )
    async throws -> HttpResponse
  {
    guard request.method == .GET else {
      return try await service(request)
    }

    if let existingRequest = cache[request] {
      return try await existingRequest.value
    }
    let task = Task {
      return try await service(request)
    }
    cache[request] = task
    defer { cache[request] = nil }
    return try await task.value
  }
}
let GlobalSingleGetFilter = SingleGetFilter()

struct NoopFilter: HttpFilter {
  func handler(request: HttpRequest, service: (HttpRequest) async throws -> HttpResponse)
    async rethrows -> HttpResponse
  {
    return try await service(request)
  }
}

func compose(filters: [HttpFilter]) -> HttpHandler {
  return { request, service in
    let composedService = filters.reversed().reduce(service) { next, filter in
      return { req in try await filter.handler(request: req, service: next) }
    }

    return try await composedService(request)
  }
}

public protocol HttpFilter: Sendable {
  func handler(
    request: HttpRequest, service: @escaping @Sendable (HttpRequest) async throws -> HttpResponse
  )
    async throws -> HttpResponse
}

import Foundation

let defaultFilters: [HttpFilter] = [
  GlobalSingleGetFilter, RetryFilter(), LoggingFilter(), ETagFilter(),
]
public let http = Http(filters: defaultFilters)

public struct Http: Sendable {
  private let handler: HttpHandler
  let session: URLSession

  public init(filters: HttpFilter...) {
    self.init(filters: filters)
  }
  public init(filters: [HttpFilter], session: URLSession = URLSession.shared) {
    handler = compose(filters: filters)
    self.session = session
  }

  public func request(_ request: HttpRequest) async throws -> HttpResponse {
    return try await handler(request) { request in
      try await basicRequest(request: request)
    }
  }

  public func download(_ request: HttpRequest, to: URL) async throws -> HttpResponse {
    return try await handler(request) { request in
      try await basicDownload(request: request, to: to)
    }
  }

  private func basicRequest(request: HttpRequest) async throws -> HttpResponse {
    guard let url = URL(string: request.path) else { throw URLError(.badURL) }
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = request.method.rawValue
    for (key, value) in request.headers {
      urlRequest.addValue(value, forHTTPHeaderField: key)
    }
    urlRequest.httpBody = request.body
    let (data, res) = try await session.data(for: urlRequest)
    guard let res = res as? HTTPURLResponse else { throw HttpError.notHttp }
    return HttpResponse(
      headers: getHeaders(res.allHeaderFields), body: data, statusCode: res.statusCode)
  }

  private func basicDownload(request: HttpRequest, to: URL) async throws -> HttpResponse {
    guard let url = URL(string: request.path) else { throw URLError(.badURL) }
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = request.method.rawValue
    for (key, value) in request.headers {
      urlRequest.addValue(value, forHTTPHeaderField: key)
    }
    urlRequest.httpBody = request.body
    let res = try await session.downloadTask(with: urlRequest, to: to)
    guard let res = res as? HTTPURLResponse else { throw HttpError.notHttp }
    return HttpResponse(
      headers: getHeaders(res.allHeaderFields), body: Data(), statusCode: res.statusCode)
  }
}

typealias HttpHandler =
  @Sendable (
    HttpRequest, @escaping @Sendable (HttpRequest) async throws -> HttpResponse
  ) async throws -> HttpResponse

public enum HttpError: Error {
  case notHttp
  case notOk(response: HttpResponse)
}

public struct HttpRequest: Equatable, Hashable, Sendable {
  public var path: String
  public var headers: [String: String] = [:]  // ideally make case insensitive dict
  public var method: HttpMethod = .GET
  public var body: Data? = nil
  public var options: HttpRequestOptions = []
  // retry for 429, 504, network error
  public var retries: Int = 0
  // public var timeoutMs: Int? = 5000

  public init(
    path: String, headers: [String: String] = [:], method: HttpMethod = .GET, body: Data? = nil,
    options: HttpRequestOptions = [], retries: Int = 0
  ) {
    self.path = path
    self.headers = headers
    self.method = method
    self.body = body
    self.options = options
    self.retries = retries
  }
  public init(
    path: String, headers: [String: String] = [:], method: HttpMethod = .GET, body: String?,
    options: HttpRequestOptions = [], retries: Int = 0
  ) {
    self.init(
      path: path, headers: headers, method: method, body: body?.data(using: .utf8),
      options: options, retries: retries
    )
  }
}
public enum HttpMethod: String, Sendable {
  case GET = "GET"
  case POST = "POST"
  case PUT = "PUT"
  case PATCH = "PATCH"
  case HEAD = "HEAD"
  case DELETE = "DELETE"
}
public struct HttpResponse: Equatable, Sendable {
  public var headers: [String: String]
  public var body: Data
  public var statusCode: Int
  public init(headers: [String: String], body: Data, statusCode: Int) {
    self.headers = headers
    self.body = body
    self.statusCode = statusCode
  }
}
extension HttpResponse {
  public var ok: Bool {
    return statusCode >= 200 && statusCode < 300
  }
}

public struct HttpRequestOptions: OptionSet, Hashable, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) {
    self.rawValue = rawValue
  }
  public static let nonHydratingEtag = HttpRequestOptions(rawValue: 1 << 0)
  public static let skipLog = HttpRequestOptions(rawValue: 2 << 0)
}

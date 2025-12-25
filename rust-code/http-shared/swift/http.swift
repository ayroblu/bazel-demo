import Foundation
import http_shared

public func registerUrlSessionHttpProvider() {
  setHttpProvider(provider: UrlSessionHttpProvider())
}

final class UrlSessionHttpProvider: HttpProvider {
  func sendRequest(request: HttpRequest) async throws -> HttpResponse {
    guard let urlItem = URL(string: request.url) else {
      throw HttpError.InvalidUrl(url: request.url)
    }
    var urlRequest = URLRequest(url: urlItem)
    urlRequest.httpMethod = httpMethodToString(method: request.method)
    if let headers = request.headers {
      for (key, value) in headers {
        urlRequest.addValue(value, forHTTPHeaderField: key)
      }
    }
    if let body = request.body {
      urlRequest.httpBody = body
    }
    let (data, res) = try await URLSession.shared.data(for: urlRequest)
    guard let res = res as? HTTPURLResponse else { throw HttpError.NotHttp }
    return HttpResponse(
      statusCode: UInt16(res.statusCode), headers: getHeaders(res.allHeaderFields), body: data)
  }
}
private nonisolated func getHeaders(_ headers: [AnyHashable: Any]) -> [String: String] {
  var responseHeaders = [String: String]()
  for (key, value) in headers {
    if let key = key as? String, let value = value as? String {
      responseHeaders[key] = value
    }
  }
  return responseHeaders
}

import FileUtils
import Foundation
import XCTest

@testable import http

func mockHttp(filters: [HttpFilter] = defaultFilters) -> Http {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [MockURLProtocol.self]
  let session = URLSession(configuration: config)
  let http = Http(filters: filters, session: session)
  return http
}

func mockResponse(path: String, response: HttpResponse) {
  let url = URL(string: path)!
  let urlResponse = HTTPURLResponse(
    url: url, statusCode: response.statusCode, httpVersion: "HTTP/2", headerFields: response.headers
  )
  MockURLProtocol.mockResponses[url] = (data: response.body, response: urlResponse, error: nil)
}

func exampleRequest() -> HttpRequest {
  let request = HttpRequest(path: "https://example.com")
  let response = HttpResponse(headers: [:], body: Data(), statusCode: 200)
  mockResponse(path: request.path, response: response)
  return request
}

class MockURLProtocol: URLProtocol {
  static var requests: [URLRequest] = []
  static var mockResponses: [URL: (data: Data?, response: URLResponse?, error: Error?)] = [:]

  override class func canInit(with request: URLRequest) -> Bool {
    return true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }

  override func startLoading() {
    MockURLProtocol.requests.append(request)
    if let url = request.url, let mockResponse = MockURLProtocol.mockResponses[url] {
      if let error = mockResponse.error {
        client?.urlProtocol(self, didFailWithError: error)
      } else {
        if let response = mockResponse.response {
          client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let data = mockResponse.data {
          client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
      }
    } else {
      client?.urlProtocol(self, didFailWithError: MockHttpError.notMocked)
    }
  }

  override func stopLoading() {
    // No action needed
  }
}
enum MockHttpError: Error {
  case notMocked
}

class HttpTestCase: XCTestCase {
  override func setUp() {
    MockURLProtocol.requests = []
    MockURLProtocol.mockResponses = [:]
  }
  override func tearDown() {
    MockURLProtocol.requests = []
    MockURLProtocol.mockResponses = [:]
  }
  override func setUpWithError() throws {
    try rm(etagDirURL)
  }
  override func tearDownWithError() throws {
    try rm(etagDirURL)
  }
}

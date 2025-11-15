import FileUtils
import XCTest

@testable import http

class FiltersTests: HttpTestCase {
  func testETagFilter() async throws {
    let http = mockHttp()
    let request = HttpRequest(
      path: "https://example.com", options: [.nonHydratingEtag])
    let data = "Hello, World!".data(using: .utf8)!
    let etag = "W/1234"
    let response = HttpResponse(headers: ["Etag": etag], body: data, statusCode: 200)
    mockResponse(path: request.path, response: response)

    // No etag saved first
    XCTAssertEqual(getEtag(urlPath: request.path), nil)

    let result = try await http.request(request)
    XCTAssertEqual(result, response)
    let savedEtag = getEtag(urlPath: request.path)
    XCTAssertEqual(savedEtag, etag)
    let reqHeader = MockURLProtocol.requests[0].value(forHTTPHeaderField: "If-None-Match")
    XCTAssertEqual(reqHeader, nil)

    // Second request has an etag
    let response2 = HttpResponse(headers: ["Etag": etag], body: Data(), statusCode: 304)
    mockResponse(path: request.path, response: response2)
    let result2 = try await http.request(request)
    XCTAssertEqual(result2, response2)
    let reqHeader2 = MockURLProtocol.requests[1].value(forHTTPHeaderField: "If-None-Match")
    XCTAssertEqual(reqHeader2, etag)
  }

  func testSingleGetFilter() async throws {
    var counter = 0
    let counterFilter = CallbackFilter(beforeCallback: { counter += 1 })
    let http = mockHttp(
      filters: defaultFilters + [counterFilter, delayResponseFilter])
    let request = exampleRequest()

    let req1 = Task { try await http.request(request) }
    try await Task.sleep(for: .milliseconds(10))
    let req2 = Task { try await http.request(request) }
    let _ = try await req1.value
    let _ = try await req2.value
    XCTAssertEqual(counter, 1)
  }

  func testFilterOrder() async throws {
    var record: [Int] = []
    let firstFilter = CallbackFilter(
      beforeCallback: { record.append(1) }, afterCallback: { record.append(2) })
    let secondFilter = CallbackFilter(
      beforeCallback: { record.append(10) }, afterCallback: { record.append(20) })
    let http = mockHttp(filters: [firstFilter, secondFilter])
    let request = exampleRequest()
    let _ = try await http.request(request)
    XCTAssertEqual(record, [1, 10, 20, 2])
  }
}

struct CallbackFilter: HttpFilter {
  let beforeCallback: () async throws -> Void
  let afterCallback: () async throws -> Void

  init(
    beforeCallback: @escaping () async throws -> Void = {},
    afterCallback: @escaping () async throws -> Void = {}
  ) {
    self.beforeCallback = beforeCallback
    self.afterCallback = afterCallback
  }

  func handler(
    request: HttpRequest,
    service: (HttpRequest) async throws -> HttpResponse
  ) async throws -> HttpResponse {
    try await beforeCallback()
    let result = try await service(request)
    try await afterCallback()
    return result
  }
}
let delayResponseFilter = CallbackFilter(afterCallback: {
  try await Task.sleep(for: .milliseconds(100))
})

import XCTest
import http

class HttpTests: HttpTestCase {
  func testFetchData_Success() async throws {
    let http = mockHttp()
    let request = HttpRequest(path: "https://example.com")
    let data = "Hello, World!".data(using: .utf8)!
    let response = HttpResponse(headers: [:], body: data, statusCode: 200)
    mockResponse(path: request.path, response: response)

    let result = try await http.request(request)
    XCTAssertEqual(result, response)
  }
}

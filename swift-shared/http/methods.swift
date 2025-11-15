import Foundation
import KVCache
import SwiftProtobuf

@concurrent
public func protoGet<T: SwiftProtobuf.Message>(_ type: T.Type, urlPath: String) async throws -> T? {
  let response = try await http.request(HttpRequest(path: urlPath, options: [.nonHydratingEtag]))
  if response.statusCode == 304 {
    return nil
  }
  if !response.ok {
    throw HttpError.notOk(response: response)
  }
  return try T(serializedBytes: response.body)
}

@concurrent
public func getJson<T>(_ type: T.Type, urlPath: String, retries: Int = 0, ttl: Date? = nil)
  async throws -> T
where T: Decodable {
  let body = try await getBody(urlPath: urlPath, retries: retries, ttl: ttl)
  let decoder = JSONDecoder()
  return try decoder.decode(type, from: body)
}

func getBody(urlPath: String, retries: Int, ttl: Date?) async throws -> Data {
  if let ttl {
    return try await getWithCache(key: urlPath) {
      let data = try await getBody(urlPath: urlPath, retries: retries)
      return (data, ttl)
    }
  }
  return try await getBody(urlPath: urlPath, retries: retries)
}
func getBody(urlPath: String, retries: Int) async throws -> Data {
  let request = HttpRequest(path: urlPath, retries: retries)
  let response = try await http.request(request)
  if !response.ok {
    throw HttpError.notOk(response: response)
  }
  return response.body
}

@concurrent
public func postJson<T>(_ type: T.Type, urlPath: String, body: String = "", retries: Int = 0)
  async throws -> T
where T: Decodable {
  let request = HttpRequest(path: urlPath, method: .POST, body: body, retries: retries)
  let response = try await http.request(request)
  if !response.ok {
    throw HttpError.notOk(response: response)
  }
  let decoder = JSONDecoder()
  return try decoder.decode(type, from: response.body)
}

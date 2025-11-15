import CryptoKit
import FileUtils
import Foundation

func getEtag(urlPath: String) -> String? {
  try? String(contentsOf: etagDirURL / MD5(urlPath), encoding: .utf8)
}
func setEtag(urlPath: String, etag: String) {
  try? mkdirp(etagDirURL)
  try? etag.write(to: etagDirURL / MD5(urlPath), atomically: true, encoding: .utf8)
}

private let cachesURL = FileManager.default.urls(
  for: .cachesDirectory, in: .userDomainMask
).first!
// test identifier is com.apple.dt.xctest.tool
let etagDirURL = cachesURL / (Bundle.main.bundleIdentifier ?? "__unknown__") / "etags"

func MD5(_ string: String) -> String {
  let digest = Insecure.MD5.hash(data: Data(string.utf8))

  return digest.map {
    String(format: "%02hhx", $0)
  }.joined()
}

func getHeaders(_ headers: [AnyHashable: Any]) -> [String: String] {
  var responseHeaders = [String: String]()
  for (key, value) in headers {
    if let key = key as? String, let value = value as? String {
      responseHeaders[key] = value
    }
  }
  return responseHeaders
}

extension URLSession {
  public func downloadTask(with url: URLRequest, to: URL) async throws -> URLResponse {
    try await withCheckedThrowingContinuation { continuation in
      let task = self.downloadTask(with: url) { localURL, response, error in
        if let error = error {
          continuation.resume(throwing: error)
          return
        }

        guard let localURL, let response else {
          continuation.resume(throwing: URLError(.badServerResponse))
          return
        }

        do {
          try FileManager.default.moveItem(at: localURL, to: to)
        } catch {
          continuation.resume(throwing: error)
          return
        }

        continuation.resume(returning: response)
      }
      task.resume()
    }
  }
}

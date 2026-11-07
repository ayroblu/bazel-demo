import Foundation
import Observation

@Observable
final class WifiProxy {
  private(set) var enabled = false
  private(set) var error: String?
  var value = UserDefaults.standard.string(forKey: "value") ?? "" {
    didSet { UserDefaults.standard.set(value, forKey: "value") }
  }

  init() {
    refresh()
  }

  func refresh() {
    Task {
      let fields = parse((try? await networksetup("-getwebproxy", service)) ?? "")
      enabled = fields["Enabled"] == "Yes"
      if value.isEmpty, let server = fields["Server"], !server.isEmpty, let port = fields["Port"] {
        value = "\(server):\(port)"
      }
    }
  }

  func set(_ on: Bool) {
    enabled = on
    Task {
      do {
        if on {
          guard let colon = value.lastIndex(of: ":"), let port = UInt16(value[colon...].dropFirst()),
            colon != value.startIndex
          else { throw Failure("Enter host:port, e.g. 192.168.1.20:8888") }
          let host = String(value[..<colon])
          try await networksetup("-setwebproxy", service, host, String(port))
          try await networksetup("-setsecurewebproxy", service, host, String(port))
        } else {
          try await networksetup("-setwebproxystate", service, "off")
          try await networksetup("-setsecurewebproxystate", service, "off")
        }
        error = nil
      } catch {
        self.error = error.localizedDescription
      }
      refresh()
    }
  }
}

private let service = "Wi-Fi"

private struct Failure: LocalizedError {
  let errorDescription: String?

  init(_ message: String) {
    errorDescription = message
  }
}

@discardableResult
@concurrent nonisolated private func networksetup(_ arguments: String...) async throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
  process.arguments = arguments
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = pipe
  try process.run()
  let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  process.waitUntilExit()
  guard process.terminationStatus == 0 else { throw Failure(output) }
  return output
}

private func parse(_ output: String) -> [String: String] {
  Dictionary(
    output.split(separator: "\n").compactMap { line in
      let parts = line.split(separator: ":", maxSplits: 1)
      guard parts.count == 2 else { return nil }
      return (String(parts[0]), parts[1].trimmingCharacters(in: .whitespaces))
    },
    uniquingKeysWith: { first, _ in first })
}

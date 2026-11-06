import Foundation

public struct GrokError: Error, Sendable {
  public let message: String
}

public enum GrokUpdate: Sendable {
  case thought(String)
  case step(String)
  case text(String)
}

@concurrent public func askGrok(
  _ question: String, onUpdate: @MainActor @Sendable (GrokUpdate) -> Void
) async throws {
  let session = UUID().uuidString.lowercased()
  let process = Process()
  process.executableURL = URL(fileURLWithPath: grokPath)
  process.arguments = [
    "-p", question, "--verbatim", "--output-format", "streaming-json", "--session-id", session,
    "--model", "grok-4.7", "--effort", "low", "--tools", "web_search,web_fetch",
    "--cwd", FileManager.default.temporaryDirectory.path, "--system-prompt-override", instructions,
  ]
  let output = Pipe()
  process.standardOutput = output
  process.standardError = FileHandle.nullDevice
  try process.run()
  defer {
    process.waitUntilExit()
    deleteSession(session)
  }
  let pid = process.processIdentifier
  let failure = try await withTaskCancellationHandler {
    try await readEvents(output.fileHandleForReading, onUpdate: onUpdate)
  } onCancel: {
    kill(pid, SIGTERM)
  }
  if let failure { throw GrokError(message: failure) }
}

private let grokPath = NSHomeDirectory() + "/.grok/bin/grok"

private let instructions = """
  You answer questions typed into a macOS launcher. Reply in plain text without Markdown. \
  Put the answer first and keep it short. Search the web when the question needs current \
  information.
  """

private func readEvents(
  _ output: FileHandle, onUpdate: @MainActor @Sendable (GrokUpdate) -> Void
) async throws -> String? {
  for try await line in output.bytes.lines {
    guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    else { continue }
    switch event["type"] as? String {
    case "thought":
      if let text = event["data"] as? String {
        await onUpdate(.thought(text))
      }
    case "tool_call":
      await onUpdate(.step(stepTitle(event)))
    case "text":
      if let text = event["data"] as? String {
        await onUpdate(.text(text))
      }
    case "error":
      return event["message"] as? String ?? "Grok couldn't answer"
    default:
      break
    }
  }
  return nil
}

private func stepTitle(_ event: [String: Any]) -> String {
  let title = event["title"] as? String ?? "Running a tool"
  switch event["kind"] as? String {
  case "search_tool": return "Looking up tools"
  case "other": return title.replacing("__", with: ": ").replacing("_", with: " ")
  default: return title
  }
}

private func deleteSession(_ session: String) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: grokPath)
  process.arguments = ["sessions", "delete", session]
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice
  try? process.run()
}

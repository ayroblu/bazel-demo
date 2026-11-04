import Foundation

nonisolated struct ProcessResult: Sendable {
  let status: Int32
  let output: Data
  let errorOutput: Data

  var errorSummary: String {
    let lines = String(decoding: errorOutput, as: UTF8.self).split(whereSeparator: \.isNewline)
    return lines.last.map(String.init) ?? "exited with status \(status)"
  }
}

@concurrent func runShell(
  _ command: String, arguments: [String] = [], in directory: URL,
  environment: [String: String], sandboxProfile: String?, timeout: Duration
) async -> ProcessResult {
  let process = Process()
  let shellArguments = ["-c", command, "sherlock"] + arguments
  if let sandboxProfile, FileManager.default.isExecutableFile(atPath: sandboxExec) {
    process.executableURL = URL(fileURLWithPath: sandboxExec)
    process.arguments = ["-p", sandboxProfile, "/bin/sh"] + shellArguments
  } else {
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = shellArguments
  }
  process.currentDirectoryURL = directory
  process.environment = environment
  let output = Pipe()
  let errorOutput = Pipe()
  process.standardOutput = output
  process.standardError = errorOutput
  process.standardInput = FileHandle.nullDevice
  let box = ProcessBox(process)
  do {
    try process.run()
  } catch {
    return ProcessResult(status: -1, output: Data(), errorOutput: Data(error.localizedDescription.utf8))
  }
  let timer = Task {
    try await Task.sleep(for: timeout)
    box.process.terminate()
  }
  return await withTaskCancellationHandler {
    async let outputData = read(output)
    async let errorData = read(errorOutput)
    let (out, err) = await (outputData, errorData)
    box.process.waitUntilExit()
    timer.cancel()
    return ProcessResult(status: box.process.terminationStatus, output: out, errorOutput: err)
  } onCancel: {
    box.process.terminate()
  }
}

nonisolated func sandboxProfile(writableFolder: URL) -> String {
  let writable = writableFolder.resolvingSymlinksInPath().path
  return """
    (version 1)
    (allow default)
    (deny file-write*)
    (allow file-write*
      (subpath "\(escape(writable))")
      (subpath "/private/var/folders")
      (subpath "/private/tmp")
      (literal "/dev/null")
      (literal "/dev/zero")
      (literal "/dev/tty")
      (regex #"^/dev/fd/"))
    """
}

@concurrent func loginShellPath() async -> String {
  let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
  let result = await runShell(
    "exec \"$1\" -l -c 'printf %s \"$PATH\"'", arguments: [shell],
    in: URL(fileURLWithPath: NSHomeDirectory()), environment: ProcessInfo.processInfo.environment,
    sandboxProfile: nil, timeout: .seconds(10))
  let path = String(decoding: result.output, as: UTF8.self)
  return result.status == 0 && !path.isEmpty ? path : fallbackPath
}

private nonisolated let sandboxExec = "/usr/bin/sandbox-exec"

private nonisolated let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

private nonisolated final class ProcessBox: @unchecked Sendable {
  let process: Process

  init(_ process: Process) {
    self.process = process
  }
}

@concurrent private func read(_ pipe: Pipe) async -> Data {
  pipe.fileHandleForReading.readDataToEndOfFile()
}

private nonisolated func escape(_ path: String) -> String {
  path.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
}

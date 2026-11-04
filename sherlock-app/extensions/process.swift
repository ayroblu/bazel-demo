import Darwin
import Foundation
import Synchronization

nonisolated struct ProcessResult: Sendable {
  let status: Int32
  let output: Data
  let errorOutput: Data
  let timeout: Duration?

  var errorSummary: String {
    if let timeout { return "Timed out after \(timeout)" }
    let lines = String(decoding: errorOutput, as: UTF8.self).split(whereSeparator: \.isNewline)
    return lines.last.map(String.init) ?? "Exited with status \(status)"
  }
}

func runShell(
  _ command: String, arguments: [String] = [], in directory: URL,
  environment: [String: String], sandboxProfile: String?, timeout: Duration
) async -> ProcessResult {
  let shell = ["/bin/sh", "-c", command, "sherlock"] + arguments
  let argv =
    if let sandboxProfile, FileManager.default.isExecutableFile(atPath: sandboxExec) {
      [sandboxExec, "-p", sandboxProfile] + shell
    } else {
      shell
    }
  let child = ChildProcess()
  return await withTaskCancellationHandler {
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(
          returning: child.run(
            argv, directory: directory.path,
            environment: environment.map { "\($0.key)=\($0.value)" }, timeout: timeout))
      }
    }
  } onCancel: {
    child.terminate()
  }
}

nonisolated func sandboxProfile(writableFolder: URL) -> String {
  let temporary = URL(fileURLWithPath: realPath(FileManager.default.temporaryDirectory))
  let writable = [
    realPath(writableFolder), temporary.path,
    temporary.deletingLastPathComponent().appending(path: "C").path, "/private/tmp",
  ]
  return """
    (version 1)
    (allow default)
    (deny file-write*)
    (allow file-write*
      \(writable.map { "(subpath \"\(escape($0))\")" }.joined(separator: "\n  "))
      (literal "/dev/null")
      (literal "/dev/zero")
      (literal "/dev/tty")
      (regex #"^/dev/fd/"))
    """
}

func loginShellPath() async -> String {
  let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
  let result = await runShell(
    "exec \"$1\" -i -l -c 'printf \"%s%s%s\" \"$2\" \"$PATH\" \"$2\"'",
    arguments: [shell, pathMarker], in: URL(fileURLWithPath: NSHomeDirectory()),
    environment: ProcessInfo.processInfo.environment, sandboxProfile: nil, timeout: .seconds(10))
  let parts = String(decoding: result.output, as: UTF8.self).components(separatedBy: pathMarker)
  return parts.count == 3 && !parts[1].isEmpty ? parts[1] : fallbackPath
}

private nonisolated let sandboxExec = "/usr/bin/sandbox-exec"

private nonisolated func realPath(_ url: URL) -> String {
  guard let resolved = realpath(url.path, nil) else { return url.path }
  defer { free(resolved) }
  return String(cString: resolved)
}

private nonisolated final class ChildProcess: Sendable {
  private let state = Mutex<(pid: pid_t, exited: Bool, cancelled: Bool, timedOut: Bool)>(
    (0, false, false, false))

  func run(_ argv: [String], directory: String, environment: [String], timeout: Duration)
    -> ProcessResult
  {
    var output: [Int32] = [0, 0]
    var errorOutput: [Int32] = [0, 0]
    pipe(&output)
    pipe(&errorOutput)
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_adddup2(&actions, output[1], 1)
    posix_spawn_file_actions_adddup2(&actions, errorOutput[1], 2)
    posix_spawn_file_actions_addchdir(&actions, directory)
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    posix_spawnattr_setflags(
      &attributes,
      Int16(
        POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK
          | POSIX_SPAWN_SETSIGDEF))
    posix_spawnattr_setpgroup(&attributes, 0)
    var noSignals = sigset_t()
    var allSignals = sigset_t()
    sigemptyset(&noSignals)
    sigfillset(&allSignals)
    posix_spawnattr_setsigmask(&attributes, &noSignals)
    posix_spawnattr_setsigdefault(&attributes, &allSignals)
    defer {
      posix_spawn_file_actions_destroy(&actions)
      posix_spawnattr_destroy(&attributes)
    }
    var pid: pid_t = 0
    let status = withCStrings(argv) { arguments in
      withCStrings(environment) { variables in
        posix_spawn(&pid, argv[0], &actions, &attributes, arguments, variables)
      }
    }
    close(output[1])
    close(errorOutput[1])
    let outputDescriptor = output[0]
    let errorDescriptor = errorOutput[0]
    guard status == 0 else {
      close(outputDescriptor)
      close(errorDescriptor)
      return ProcessResult(
        status: -1, output: Data(), errorOutput: Data(String(cString: strerror(status)).utf8),
        timeout: nil)
    }
    let cancelledEarly = state.withLock {
      $0.pid = pid
      return $0.cancelled
    }
    if cancelledEarly {
      terminate()
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout.seconds) {
      if self.isRunning {
        self.state.withLock { $0.timedOut = true }
        self.terminate()
      }
    }
    let reads = DispatchGroup()
    let outputData = OutputBuffer()
    let errorData = OutputBuffer()
    DispatchQueue.global().async(group: reads) {
      outputData.data = readAll(outputDescriptor)
    }
    DispatchQueue.global().async(group: reads) {
      errorData.data = readAll(errorDescriptor)
    }
    var exitStatus: Int32 = 0
    waitpid(pid, &exitStatus, 0)
    let timedOut = state.withLock { state -> Bool in
      state.exited = true
      return state.timedOut
    }
    kill(-pid, SIGKILL)
    reads.wait()
    let code = (exitStatus & 0x7f) == 0 ? (exitStatus >> 8) & 0xff : 128 + (exitStatus & 0x7f)
    return ProcessResult(
      status: code, output: outputData.data, errorOutput: errorData.data,
      timeout: timedOut ? timeout : nil)
  }

  func terminate() {
    let pid = state.withLock { state -> pid_t in
      state.cancelled = true
      return state.exited ? 0 : state.pid
    }
    guard pid > 0 else { return }
    kill(-pid, SIGTERM)
    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
      if self.isRunning {
        kill(-pid, SIGKILL)
      }
    }
  }

  private var isRunning: Bool {
    state.withLock { $0.pid > 0 && !$0.exited }
  }
}

private nonisolated final class OutputBuffer: @unchecked Sendable {
  var data = Data()
}

private nonisolated func withCStrings<Result>(
  _ strings: [String], _ body: ([UnsafeMutablePointer<CChar>?]) -> Result
) -> Result {
  let pointers = strings.map { strdup($0) } + [nil]
  defer { pointers.forEach { free($0) } }
  return body(pointers)
}

private nonisolated func readAll(_ descriptor: Int32) -> Data {
  let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
  return handle.readDataToEndOfFile()
}

private nonisolated extension Duration {
  var seconds: Double {
    Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}

private nonisolated let pathMarker = "__SHERLOCK_PATH__"

private nonisolated let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

private nonisolated func escape(_ path: String) -> String {
  path.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
}

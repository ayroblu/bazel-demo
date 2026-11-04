import CryptoKit
import Foundation
import Observation
import Yams

public nonisolated struct ExtensionCommand: Sendable, Equatable {
  public let folder: String
  public let keyword: String
  public let title: String
  let script: String
  let action: String?

  public var hasAction: Bool { action != nil }
}

public nonisolated struct ExtensionItem: Decodable, Sendable {
  public let title: String
  public let subtitle: String?
  public let arg: String?
  public let url: String?
  public let copy: String?
  public let autocomplete: String?
  public let icon: String?
}

public nonisolated enum ExtensionStatus: Sendable, Equatable {
  case settingUp
  case ready
  case failed(String)
}

public nonisolated struct ExtensionSummary: Sendable, Identifiable {
  public let id: String
  public let name: String
  public let status: ExtensionStatus
}

@Observable
public final class Extensions {
  public var onChange: () -> Void = {}
  public private(set) var commands: [ExtensionCommand] = []
  public private(set) var summaries: [ExtensionSummary] = []
  @ObservationIgnored private var folder: URL
  @ObservationIgnored private var loaded: [String: LoadedExtension] = [:]
  @ObservationIgnored private var builds: [String: Task<Void, Never>] = [:]
  @ObservationIgnored private var loginPath: Task<String, Never>?
  @ObservationIgnored private var isScanning = false
  @ObservationIgnored private var needsRescan = false

  public init(configFolder: URL) {
    folder = configFolder.appending(path: extensionsFolderName)
    reload()
  }

  public var folderURL: URL { folder }

  public func reload() {
    guard !isScanning else {
      needsRescan = true
      return
    }
    isScanning = true
    let folder = folder
    Task {
      let scanned = await scanExtensions(in: folder)
      apply(scanned)
      isScanning = false
      if needsRescan {
        needsRescan = false
        reload()
      }
    }
  }

  public func moveFolder(to configFolder: URL) throws {
    let destination = configFolder.appending(path: extensionsFolderName)
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: folder.path), !fileManager.fileExists(atPath: destination.path) {
      try fileManager.moveItem(at: folder, to: destination)
    }
    folder = destination
    reload()
  }

  public func status(of command: ExtensionCommand) -> ExtensionStatus {
    loaded[command.folder]?.status ?? .failed("Extension not found")
  }

  public func buildFolder(of command: ExtensionCommand) -> URL {
    buildsURL.appending(path: command.folder)
  }

  public func run(_ command: ExtensionCommand, query: String) async -> Result<[ExtensionItem], ExtensionError> {
    await builds[command.folder]?.value
    if Task.isCancelled { return .success([]) }
    guard status(of: command) == .ready else {
      return .failure(ExtensionError(message: "\(command.title) isn't set up"))
    }
    let result = await runShell(
      command.script, arguments: [query], in: buildFolder(of: command),
      environment: await environment(for: command.folder, query: query),
      sandboxProfile: sandboxProfile(writableFolder: dataURL.appending(path: command.folder)),
      timeout: .seconds(15))
    if Task.isCancelled { return .success([]) }
    guard result.status == 0 else {
      return .failure(ExtensionError(message: result.errorSummary))
    }
    do {
      return .success(try JSONDecoder().decode(ExtensionOutput.self, from: result.output).items)
    } catch {
      return .failure(ExtensionError(message: "Couldn't read the script's output: \(error.localizedDescription)"))
    }
  }

  public func runAction(_ command: ExtensionCommand, arg: String) async -> ExtensionError? {
    guard let action = command.action else { return nil }
    let result = await runShell(
      action, arguments: [arg], in: buildFolder(of: command),
      environment: await environment(for: command.folder, query: arg),
      sandboxProfile: sandboxProfile(writableFolder: dataURL.appending(path: command.folder)),
      timeout: .seconds(60))
    return result.status == 0 ? nil : ExtensionError(message: result.errorSummary)
  }

  private func apply(_ scanned: [ScannedExtension]) {
    var next: [String: LoadedExtension] = [:]
    for extensionInfo in scanned {
      let previous = loaded[extensionInfo.folder]
      let sameFiles = previous?.info.fingerprint == extensionInfo.fingerprint
      let status: ExtensionStatus
      if let error = extensionInfo.error {
        status = .failed(error)
      } else if extensionInfo.fingerprint == extensionInfo.builtFingerprint {
        status = .ready
      } else if sameFiles, let previous, previous.status != .ready {
        status = previous.status
      } else if sameFiles, FileManager.default.fileExists(
        atPath: buildsURL.appending(path: extensionInfo.folder).path)
      {
        status = .ready
      } else {
        status = .settingUp
        startBuild(extensionInfo)
      }
      next[extensionInfo.folder] = LoadedExtension(info: extensionInfo, status: status)
    }
    for removed in Set(loaded.keys).subtracting(next.keys) {
      builds.removeValue(forKey: removed)?.cancel()
      try? FileManager.default.removeItem(at: buildsURL.appending(path: removed))
    }
    loaded = next
    publish()
  }

  private func startBuild(_ extensionInfo: ScannedExtension) {
    builds[extensionInfo.folder]?.cancel()
    builds[extensionInfo.folder] = Task {
      let error = await buildExtension(
        extensionInfo, environment: await environment(for: extensionInfo.folder, query: ""))
      guard !Task.isCancelled else { return }
      builds[extensionInfo.folder] = nil
      guard loaded[extensionInfo.folder]?.info.fingerprint == extensionInfo.fingerprint else { return }
      loaded[extensionInfo.folder]?.status = error.map { .failed($0) } ?? .ready
      publish()
    }
  }

  private func publish() {
    let entries = loaded.values.sorted { $0.info.folder < $1.info.folder }
    commands = entries.flatMap { entry in
      (entry.info.manifest?.commands ?? []).map {
        ExtensionCommand(
          folder: entry.info.folder, keyword: $0.keyword, title: $0.title, script: $0.script,
          action: $0.action)
      }
    }
    summaries = entries.map {
      ExtensionSummary(id: $0.info.folder, name: $0.info.manifest?.name ?? $0.info.folder, status: $0.status)
    }
    onChange()
  }

  private func environment(for folder: String, query: String) async -> [String: String] {
    let path = loginPath ?? Task { await loginShellPath() }
    loginPath = path
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = await path.value
    environment["SHERLOCK_EXTENSION_DATA"] = dataURL.appending(path: folder).path
    environment["SHERLOCK_QUERY"] = query
    return environment
  }
}

public nonisolated struct ExtensionError: Error, Sendable {
  public let message: String
}

private nonisolated struct ExtensionOutput: Decodable {
  let items: [ExtensionItem]
}

private nonisolated struct Manifest: Decodable, Sendable {
  struct Command: Decodable, Sendable {
    let keyword: String
    let title: String
    let script: String
    let action: String?
  }

  let name: String?
  let setup: String?
  let commands: [Command]
}

private nonisolated struct ScannedExtension: Sendable {
  let folder: String
  let source: URL
  let manifest: Manifest?
  let error: String?
  let fingerprint: String
  let builtFingerprint: String?
}

private nonisolated struct LoadedExtension {
  let info: ScannedExtension
  var status: ExtensionStatus
}

private nonisolated let extensionsFolderName = "extensions"

private nonisolated let manifestName = "extension.yaml"

private nonisolated let buildMarkerName = ".sherlock-build"

private nonisolated let setupLogName = ".sherlock-setup.log"

private nonisolated let excludedNames: Set<String> = [".git", "node_modules", "data", ".DS_Store"]

private nonisolated let buildsURL = URL.cachesDirectory.appending(
  path: "com.ayroblu.sherlock/Extensions")

private nonisolated let dataURL = URL.applicationSupportDirectory.appending(
  path: "Sherlock/Extension Data")

@concurrent private func scanExtensions(in folder: URL) async -> [ScannedExtension] {
  let fileManager = FileManager.default
  let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
  return names.sorted().compactMap { name -> ScannedExtension? in
    let source = folder.appending(path: name)
    let manifestURL = source.appending(path: manifestName)
    guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
    var manifest: Manifest?
    var manifestError: String?
    do {
      manifest = try YAMLDecoder().decode(
        Manifest.self, from: String(contentsOf: manifestURL, encoding: .utf8))
    } catch {
      manifestError = "extension.yaml: \(error.localizedDescription)"
    }
    let built = try? String(
      contentsOf: buildsURL.appending(path: name).appending(path: buildMarkerName), encoding: .utf8)
    return ScannedExtension(
      folder: name, source: source, manifest: manifest, error: manifestError,
      fingerprint: fingerprint(of: source), builtFingerprint: built)
  }
}

private nonisolated func fingerprint(of folder: URL) -> String {
  var hash = SHA256()
  let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
  let enumerator = FileManager.default.enumerator(
    at: folder, includingPropertiesForKeys: keys,
    errorHandler: nil)
  var entries: [String] = []
  while let url = enumerator?.nextObject() as? URL {
    if enumerator?.level == 1, excludedNames.contains(url.lastPathComponent) {
      enumerator?.skipDescendants()
      continue
    }
    if url.lastPathComponent == ".DS_Store" {
      continue
    }
    let values = try? url.resourceValues(forKeys: Set(keys))
    guard values?.isRegularFile == true else { continue }
    let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
    entries.append("\(url.path.dropFirst(folder.path.count))|\(values?.fileSize ?? 0)|\(modified)")
  }
  for entry in entries.sorted() {
    hash.update(data: Data(entry.utf8))
  }
  return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

@concurrent private func buildExtension(
  _ extensionInfo: ScannedExtension, environment: [String: String]
) async -> String? {
  let fileManager = FileManager.default
  let build = buildsURL.appending(path: extensionInfo.folder)
  let data = dataURL.appending(path: extensionInfo.folder)
  do {
    try? fileManager.removeItem(at: build)
    try fileManager.createDirectory(at: build, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: data, withIntermediateDirectories: true)
    for name in try fileManager.contentsOfDirectory(atPath: extensionInfo.source.path)
    where !excludedNames.contains(name) {
      try fileManager.copyItem(
        at: extensionInfo.source.appending(path: name), to: build.appending(path: name))
    }
    try fileManager.createSymbolicLink(at: build.appending(path: "data"), withDestinationURL: data)
  } catch {
    return "Couldn't copy the extension: \(error.localizedDescription)"
  }
  if let setup = extensionInfo.manifest?.setup {
    let result = await runShell(
      setup, in: build, environment: environment, sandboxProfile: nil, timeout: .seconds(600))
    var log = result.output
    log.append(result.errorOutput)
    try? log.write(to: build.appending(path: setupLogName))
    guard result.status == 0 else { return "Setup failed: \(result.errorSummary)" }
  }
  try? extensionInfo.fingerprint.write(
    to: build.appending(path: buildMarkerName), atomically: true, encoding: .utf8)
  return nil
}

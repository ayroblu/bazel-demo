import AppKit
import CoreServices
import Observation
import hotkey
import preferences

public nonisolated struct HotkeyStatus: Identifiable, Sendable {
  public let id: Int
  public let shortcut: String
  public let target: String
  public let error: String?
}

@Observable
public final class HotkeyBindings {
  public var onSearch: (String) -> Void = { _ in }
  public private(set) var statuses: [HotkeyStatus] = []
  @ObservationIgnored private var bindings: [HotkeyBinding] = []
  @ObservationIgnored private var hotKeys: [HotKey] = []
  @ObservationIgnored private var isPaused = false

  public init() {}

  public func apply(_ bindings: [HotkeyBinding]) {
    self.bindings = bindings
    register()
  }

  public func setPaused(_ paused: Bool) {
    guard paused != isPaused else { return }
    isPaused = paused
    register()
  }

  private func register() {
    hotKeys = []
    statuses = bindings.enumerated().map { index, binding in
      let target = describe(binding)
      guard let shortcut = Shortcut(spec: binding.hotkey) else {
        return HotkeyStatus(
          id: index, shortcut: binding.hotkey, target: target,
          error: "Unknown hotkey. Use hyper, cmd, ctrl, alt or shift, then a key, like hyper+t.")
      }
      let action: () -> Void
      switch (binding.app, binding.search, binding.applescript) {
      case (let app?, nil, nil):
        guard let url = appURL(named: app) else {
          return HotkeyStatus(
            id: index, shortcut: shortcut.description, target: target,
            error: "Couldn't find an app called ‘\(app)’")
        }
        let followsDefaultBrowser = app.lowercased() == defaultBrowser
        action = { focus(followsDefaultBrowser ? appURL(named: app) ?? url : url) }
      case (nil, let text?, nil):
        action = { [weak self] in self?.onSearch(text) }
      case (nil, nil, let script?):
        action = { runAppleScript(script) }
      default:
        return HotkeyStatus(
          id: index, shortcut: shortcut.description, target: target,
          error: "Set exactly one of app, search or applescript")
      }
      guard !isPaused else {
        return HotkeyStatus(id: index, shortcut: shortcut.description, target: target, error: nil)
      }
      let hotKey = HotKey(action: action)
      hotKeys.append(hotKey)
      let registered = hotKey.register(shortcut)
      return HotkeyStatus(
        id: index, shortcut: shortcut.description, target: target,
        error: registered ? nil : "Couldn't register this hotkey; another hotkey may already use it")
    }
  }
}

private func describe(_ binding: HotkeyBinding) -> String {
  if let app = binding.app { return app }
  if let search = binding.search { return "Search ‘\(search.trimmingCharacters(in: .whitespaces))’" }
  if binding.applescript != nil { return "AppleScript" }
  return "Nothing"
}

private func appURL(named name: String) -> URL? {
  if name.lowercased() == defaultBrowser {
    return NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
  }
  let expanded = (name as NSString).expandingTildeInPath
  if expanded.hasSuffix(".app"), FileManager.default.fileExists(atPath: expanded) {
    return URL(fileURLWithPath: expanded)
  }
  if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
    return url
  }
  for folder in applicationFolders {
    let url = URL(fileURLWithPath: folder).appending(path: name + ".app")
    if FileManager.default.fileExists(atPath: url.path) {
      return url
    }
  }
  return spotlightApp(named: name)
}

private let defaultBrowser = "default browser"

private let applicationFolders = [
  "/Applications", "/Applications/Utilities", "/System/Applications",
  "/System/Applications/Utilities", NSHomeDirectory() + "/Applications",
  "/System/Library/CoreServices", "/System/Library/CoreServices/Applications",
]

private func spotlightApp(named name: String) -> URL? {
  let escaped = name.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
  let query = MDQueryCreate(
    kCFAllocatorDefault,
    "kMDItemContentType == \"com.apple.application-bundle\" && kMDItemFSName == \"\(escaped).app\"c"
      as CFString, nil, nil)!
  MDQuerySetMaxCount(query, 1)
  MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue))
  guard MDQueryGetResultCount(query) > 0 else { return nil }
  let item = unsafeBitCast(MDQueryGetResultAtIndex(query, 0), to: MDItem.self)
  return (MDItemCopyAttribute(item, kMDItemPath) as? String).map(URL.init(fileURLWithPath:))
}

private func focus(_ url: URL) {
  let configuration = NSWorkspace.OpenConfiguration()
  configuration.activates = true
  NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
}

private func runAppleScript(_ script: String) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
  process.arguments = ["-e", script]
  let errorOutput = Pipe()
  process.standardError = errorOutput
  process.standardOutput = FileHandle.nullDevice
  process.terminationHandler = { process in
    guard process.terminationStatus != 0 else { return }
    let message = String(
      decoding: errorOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    Task { @MainActor in
      let alert = NSAlert()
      alert.messageText = "AppleScript hotkey failed"
      alert.informativeText = message
      NSApp.activate()
      alert.window.level = .floating
      alert.runModal()
    }
  }
  try? process.run()
}

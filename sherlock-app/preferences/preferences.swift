import AppKit
import Carbon.HIToolbox
import Observation
import Yams
import hotkey

@Observable
public final class Preferences {
  public var shortcut: Shortcut { didSet { save() } }
  public var clipboardShortcut: Shortcut { didSet { save() } }
  public var showMenuBarIcon: Bool { didSet { save() } }
  public var searchFiles: Bool { didSet { save() } }
  public var clipboardHistory: Bool { didSet { save() } }
  public var clipboardRetentionDays: Int { didSet { save() } }
  public var expandSnippets: Bool { didSet { save() } }
  public var autoPaste: Bool { didSet { save() } }
  public var clipboardKeyword: String { didSet { save() } }
  public var snippetKeyword: String { didSet { save() } }
  public private(set) var configFolder: URL
  public var isRecordingShortcut = false
  public var hotKeyRegistered = true
  public var clipboardHotKeyRegistered = true

  public static let standardClipboardShortcut = Shortcut(
    keyCode: UInt32(kVK_ANSI_C),
    modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue, key: "C")

  public static let standardConfigFolder = URL.applicationSupportDirectory.appending(
    path: "Sherlock")

  public init() {
    let folder =
      UserDefaults.standard.string(forKey: configFolderKey).map { URL(fileURLWithPath: $0) }
      ?? Self.standardConfigFolder
    configFolder = folder
    let file = settingsFile(in: folder)
    let stored = loadSettings(file) ?? StoredSettings()
    shortcut = stored.shortcut
    clipboardShortcut = stored.clipboardShortcut
    showMenuBarIcon = stored.showMenuBarIcon
    searchFiles = stored.searchFiles
    clipboardHistory = stored.clipboardHistory
    clipboardRetentionDays = stored.clipboardRetentionDays
    expandSnippets = stored.expandSnippets
    autoPaste = stored.autoPaste
    clipboardKeyword = stored.clipboardKeyword
    snippetKeyword = stored.snippetKeyword
    if !FileManager.default.fileExists(atPath: file.path) {
      save()
    }
  }

  public func moveConfigFolder(to folder: URL) throws {
    let file = try moveDataFile(settingsFile(in: configFolder), into: folder)
    configFolder = folder
    UserDefaults.standard.set(folder.path, forKey: configFolderKey)
    guard let stored = loadSettings(file) else {
      save()
      return
    }
    apply(stored)
  }

  private func apply(_ stored: StoredSettings) {
    shortcut = stored.shortcut
    clipboardShortcut = stored.clipboardShortcut
    showMenuBarIcon = stored.showMenuBarIcon
    searchFiles = stored.searchFiles
    clipboardHistory = stored.clipboardHistory
    clipboardRetentionDays = stored.clipboardRetentionDays
    expandSnippets = stored.expandSnippets
    autoPaste = stored.autoPaste
    clipboardKeyword = stored.clipboardKeyword
    snippetKeyword = stored.snippetKeyword
  }

  private func save() {
    let stored = StoredSettings(
      shortcut: shortcut, clipboardShortcut: clipboardShortcut, showMenuBarIcon: showMenuBarIcon,
      searchFiles: searchFiles, clipboardHistory: clipboardHistory,
      clipboardRetentionDays: clipboardRetentionDays, expandSnippets: expandSnippets,
      autoPaste: autoPaste, clipboardKeyword: clipboardKeyword, snippetKeyword: snippetKeyword)
    try? FileManager.default.createDirectory(at: configFolder, withIntermediateDirectories: true)
    try? encodeYAML(stored).write(to: settingsFile(in: configFolder), atomically: true, encoding: .utf8)
  }
}

public func encodeYAML(_ value: some Encodable) throws -> String {
  let encoder = YAMLEncoder()
  encoder.options.allowUnicode = true
  encoder.options.sortKeys = true
  encoder.options.width = -1
  encoder.options.newLineScalarStyle = .literal
  return try encoder.encode(value)
}

public func decodeYAML<T: Decodable>(_ type: T.Type, from file: URL) -> T? {
  (try? String(contentsOf: file, encoding: .utf8)).flatMap { try? YAMLDecoder().decode(type, from: $0) }
}

public func moveDataFile(_ file: URL, into folder: URL) throws -> URL {
  let destination = folder.appending(path: file.lastPathComponent)
  let fileManager = FileManager.default
  try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
  if fileManager.fileExists(atPath: file.path), !fileManager.fileExists(atPath: destination.path) {
    try fileManager.moveItem(at: file, to: destination)
  }
  return destination
}

private let configFolderKey = "configFolder"

private func settingsFile(in folder: URL) -> URL {
  folder.appending(path: "settings.yaml")
}

private struct StoredSettings: Codable {
  var shortcut = Shortcut.standard
  var clipboardShortcut = Preferences.standardClipboardShortcut
  var showMenuBarIcon = true
  var searchFiles = true
  var clipboardHistory = true
  var clipboardRetentionDays = 7
  var expandSnippets = false
  var autoPaste = false
  var clipboardKeyword = "clip"
  var snippetKeyword = "snip"
}

extension StoredSettings {
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let standard = StoredSettings()
    shortcut = try container.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? standard.shortcut
    clipboardShortcut =
      try container.decodeIfPresent(Shortcut.self, forKey: .clipboardShortcut)
      ?? standard.clipboardShortcut
    showMenuBarIcon =
      try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? standard.showMenuBarIcon
    searchFiles =
      try container.decodeIfPresent(Bool.self, forKey: .searchFiles) ?? standard.searchFiles
    clipboardHistory =
      try container.decodeIfPresent(Bool.self, forKey: .clipboardHistory)
      ?? standard.clipboardHistory
    clipboardRetentionDays =
      try container.decodeIfPresent(Int.self, forKey: .clipboardRetentionDays)
      ?? standard.clipboardRetentionDays
    expandSnippets =
      try container.decodeIfPresent(Bool.self, forKey: .expandSnippets) ?? standard.expandSnippets
    autoPaste = try container.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? standard.autoPaste
    clipboardKeyword =
      try container.decodeIfPresent(String.self, forKey: .clipboardKeyword)
      ?? standard.clipboardKeyword
    snippetKeyword =
      try container.decodeIfPresent(String.self, forKey: .snippetKeyword) ?? standard.snippetKeyword
  }
}

private func loadSettings(_ file: URL) -> StoredSettings? {
  decodeYAML(StoredSettings.self, from: file)
}

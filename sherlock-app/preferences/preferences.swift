import AppKit
import Carbon.HIToolbox
import Observation
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
  public var recordingShortcut: String?
  public var hotKeyRegistered = true
  public var clipboardHotKeyRegistered = true
  @ObservationIgnored private let file: ConfigFile<StoredSettings>
  @ObservationIgnored private var isApplying = false
  @ObservationIgnored private var fileIsInvalid = false

  public static let standardClipboardShortcut = Shortcut(
    keyCode: UInt32(kVK_ANSI_C),
    modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue, key: "C")

  public static let standardConfigFolder = URL.applicationSupportDirectory.appending(
    path: "Sherlock", directoryHint: .isDirectory)

  public init() {
    let folder =
      UserDefaults.standard.string(forKey: configFolderKey).map {
        URL(filePath: $0, directoryHint: .isDirectory)
      } ?? Self.standardConfigFolder
    configFolder = folder
    file = ConfigFile(folder: folder, name: "settings.yaml")
    let loaded = file.load()
    fileIsInvalid = loaded == nil && file.exists
    let stored = loaded ?? StoredSettings()
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
    if !file.exists {
      save()
    }
  }

  public func reloadIfChanged() {
    guard file.hasChanged, let loaded = loadFile() else { return }
    apply(loaded)
  }

  public func moveConfigFolder(to folder: URL) throws {
    try file.move(to: folder)
    configFolder = folder
    UserDefaults.standard.set(folder.path, forKey: configFolderKey)
    if let loaded = loadFile() {
      apply(loaded)
    } else {
      save()
    }
  }

  private func loadFile() -> StoredSettings? {
    let loaded = file.load()
    fileIsInvalid = loaded == nil && file.exists
    return loaded
  }

  private func apply(_ stored: StoredSettings) {
    isApplying = true
    defer { isApplying = false }
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
    guard !isApplying, !fileIsInvalid else { return }
    try? file.save(
      StoredSettings(
        shortcut: shortcut, clipboardShortcut: clipboardShortcut, showMenuBarIcon: showMenuBarIcon,
        searchFiles: searchFiles, clipboardHistory: clipboardHistory,
        clipboardRetentionDays: clipboardRetentionDays, expandSnippets: expandSnippets,
        autoPaste: autoPaste, clipboardKeyword: clipboardKeyword, snippetKeyword: snippetKeyword))
  }
}

private let configFolderKey = "configFolder"

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

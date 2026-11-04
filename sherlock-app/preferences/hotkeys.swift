import Foundation

public nonisolated struct HotkeyBinding: Codable, Sendable, Equatable {
  public var hotkey: String
  public var app: String?
  public var search: String?
  public var applescript: String?
}

public typealias HotkeyStore = ConfigList<HotkeyBinding>

extension ConfigList where Item == HotkeyBinding {
  public convenience init(hotkeysIn folder: URL) {
    self.init(folder: folder, name: "hotkeys.yaml")
  }
}

import Foundation

public nonisolated struct HotkeyBinding: Codable, Sendable, Equatable {
  public var hotkey: String
  public var app: String?
  public var search: String?
  public var applescript: String?
}

public final class HotkeyStore {
  public var onChange: () -> Void = {}
  public private(set) var bindings: [HotkeyBinding] = []
  private let file: ConfigFile<[HotkeyBinding]>

  public init(folder: URL) {
    file = ConfigFile(folder: folder, name: "hotkeys.yaml")
    load()
  }

  public var fileURL: URL { file.url }

  public func reloadIfChanged() {
    guard file.hasChanged else { return }
    load()
  }

  public func moveFolder(to folder: URL) throws {
    try file.move(to: folder)
    load()
  }

  private func load() {
    guard let loaded = file.load() ?? (file.exists ? nil : []) else { return }
    bindings = loaded
    onChange()
  }
}

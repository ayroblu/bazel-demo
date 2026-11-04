import AppKit
import Carbon.HIToolbox

public struct Shortcut: Codable, Equatable, Sendable {
  public var keyCode: UInt32
  public var modifiers: UInt
  public var key: String

  public static let standard = Shortcut(
    keyCode: UInt32(kVK_Space), modifiers: NSEvent.ModifierFlags.command.rawValue, key: "Space")

  public init(keyCode: UInt32, modifiers: UInt, key: String) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.key = key
  }

  public init?(event: NSEvent) {
    let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    let isFunctionKey = functionKeyCodes.contains(Int(event.keyCode))
    guard !flags.subtracting(.shift).isEmpty || isFunctionKey else { return nil }
    keyCode = UInt32(event.keyCode)
    modifiers = flags.rawValue
    key =
      specialKeyNames[Int(event.keyCode)]
      ?? event.characters(byApplyingModifiers: [])?.uppercased()
      ?? "?"
  }

  public var description: String {
    var result = ""
    if flags.contains(.control) { result += "⌃" }
    if flags.contains(.option) { result += "⌥" }
    if flags.contains(.shift) { result += "⇧" }
    if flags.contains(.command) { result += "⌘" }
    return result + key
  }

  var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

  var carbonModifiers: UInt32 {
    var result = 0
    if flags.contains(.command) { result |= cmdKey }
    if flags.contains(.option) { result |= optionKey }
    if flags.contains(.control) { result |= controlKey }
    if flags.contains(.shift) { result |= shiftKey }
    return UInt32(result)
  }
}

public func isSystemShortcut(_ shortcut: Shortcut) -> Bool {
  let domain = "com.apple.symbolichotkeys" as CFString
  CFPreferencesAppSynchronize(domain)
  guard
    let hotKeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain)
      as? [String: Any]
  else { return shortcut == .standard }
  if shortcut == .standard, hotKeys[spotlightHotKeyId] == nil { return true }
  return hotKeys.values.contains { value in
    guard let entry = value as? [String: Any], entry["enabled"] as? Bool == true,
      let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Int],
      parameters.count == 3
    else { return false }
    return parameters[1] == Int(shortcut.keyCode) && parameters[2] == Int(shortcut.modifiers)
  }
}

private let functionKeyCodes: Set<Int> = [
  kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
  kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
]

private let specialKeyNames: [Int: String] = [
  kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
  kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→",
  kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
  kVK_PageUp: "⇞", kVK_PageDown: "⇟",
  kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
  kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
  kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
  kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
]

private let spotlightHotKeyId = "64"

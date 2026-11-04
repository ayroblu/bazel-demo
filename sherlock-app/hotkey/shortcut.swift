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
    guard canBeHotKey(Int(event.keyCode), flags) else { return nil }
    keyCode = UInt32(event.keyCode)
    modifiers = flags.rawValue
    key =
      specialKeyNames[Int(event.keyCode)]
      ?? event.characters(byApplyingModifiers: [])?.uppercased()
      ?? "?"
  }

  public init?(spec: String) {
    let parts = spec.lowercased().split(separator: "+").map {
      $0.trimmingCharacters(in: .whitespaces)
    }
    guard let keyName = parts.last, let key = specKeys[keyName] else { return nil }
    var flags: NSEvent.ModifierFlags = []
    for modifier in parts.dropLast() {
      guard let modifierFlags = specModifiers[modifier] else { return nil }
      flags.formUnion(modifierFlags)
    }
    guard canBeHotKey(key.code, flags) else { return nil }
    self.init(keyCode: UInt32(key.code), modifiers: flags.rawValue, key: key.label)
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

private func canBeHotKey(_ keyCode: Int, _ flags: NSEvent.ModifierFlags) -> Bool {
  !flags.subtracting(.shift).isEmpty || functionKeys.contains(keyCode)
}

private let functionKeys = [
  kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
  kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
]

private let specialKeyNames: [Int: String] = [
  kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
  kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→",
  kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
  kVK_PageUp: "⇞", kVK_PageDown: "⇟",
].merging(functionKeys.enumerated().map { ($1, "F\($0 + 1)") }) { $1 }

private let specKeys: [String: (code: Int, label: String)] = {
  var keys: [String: (code: Int, label: String)] = [:]
  let letters = [
    kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G,
    kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N,
    kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U,
    kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z,
  ]
  for (offset, code) in letters.enumerated() {
    let letter = String(UnicodeScalar(UInt8(97 + offset)))
    keys[letter] = (code, letter.uppercased())
  }
  let digits = [
    kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6,
    kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
  ]
  for (digit, code) in digits.enumerated() {
    keys[String(digit)] = (code, String(digit))
  }
  for (offset, code) in functionKeys.enumerated() {
    keys["f\(offset + 1)"] = (code, "F\(offset + 1)")
  }
  let named: [(names: [String], code: Int)] = [
    (["space"], kVK_Space), (["return", "enter"], kVK_Return), (["tab"], kVK_Tab),
    (["escape", "esc"], kVK_Escape), (["delete", "backspace"], kVK_Delete),
    (["left"], kVK_LeftArrow), (["right"], kVK_RightArrow), (["up"], kVK_UpArrow),
    (["down"], kVK_DownArrow), ([","], kVK_ANSI_Comma), (["."], kVK_ANSI_Period),
    (["/"], kVK_ANSI_Slash), ([";"], kVK_ANSI_Semicolon), (["'"], kVK_ANSI_Quote),
    (["["], kVK_ANSI_LeftBracket), (["]"], kVK_ANSI_RightBracket),
    (["\\"], kVK_ANSI_Backslash), (["-"], kVK_ANSI_Minus), (["="], kVK_ANSI_Equal),
    (["`"], kVK_ANSI_Grave),
  ]
  for entry in named {
    for name in entry.names {
      keys[name] = (entry.code, specialKeyNames[entry.code] ?? name.uppercased())
    }
  }
  return keys
}()

private let specModifiers: [String: NSEvent.ModifierFlags] = [
  "hyper": [.command, .option, .control, .shift], "cmd": .command, "command": .command,
  "⌘": .command, "ctrl": .control, "control": .control, "⌃": .control, "alt": .option,
  "opt": .option, "option": .option, "⌥": .option, "shift": .shift, "⇧": .shift,
]

private let spotlightHotKeyId = "64"

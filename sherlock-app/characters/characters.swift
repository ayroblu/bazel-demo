import Foundation

public struct CharacterEntry: Sendable {
  public let id: String
  public let text: String
  public let title: String
  public let subtitle: String
  public let names: [String]
  public let keywords: [String]
}

public func loadEmoji() -> [CharacterEntry] {
  guard let emoji = readJSON("compact") as? [[String: Any]] else { return [] }
  let shortcodes = readJSON("iamcal") as? [String: Any] ?? [:]
  return emoji.compactMap { item in
    guard let label = item["label"] as? String, let text = item["unicode"] as? String,
      let hexcode = item["hexcode"] as? String, let group = item["group"] as? Int,
      group != componentGroup
    else { return nil }
    let codes = shortcodes[hexcode].map { $0 as? [String] ?? [$0 as? String].compactMap(\.self) } ?? []
    let tags = item["tags"] as? [String] ?? []
    return CharacterEntry(
      id: "emoji:" + hexcode, text: text, title: label.prefix(1).uppercased() + label.dropFirst(),
      subtitle: [codes.map { ":\($0):" }.joined(separator: " "), tags.joined(separator: ", ")]
        .filter { !$0.isEmpty }.joined(separator: " · "),
      names: [label] + codes, keywords: tags)
  }
}

public func loadSymbols() -> [CharacterEntry] {
  let keys = keyAliases.compactMap { text, aliases in
    text.unicodeScalars.first.flatMap { symbolEntry($0, aliases: aliases) }
  }
  let keyTexts = Set(keyAliases.map(\.text))
  let others = (0...0x10FFFF).lazy.compactMap(Unicode.Scalar.init).filter {
    isSymbol($0) && !keyTexts.contains(String($0))
  }.compactMap { symbolEntry($0, aliases: []) }
  return keys + others
}

private func readJSON(_ name: String) -> Any? {
  Bundle.main.url(forResource: name, withExtension: "json")
    .flatMap { try? Data(contentsOf: $0) }
    .flatMap { try? JSONSerialization.jsonObject(with: $0) }
}

private let componentGroup = 2

private let keyAliases: [(text: String, aliases: [String])] = [
  ("⌘", ["command", "cmd"]), ("⌥", ["option", "alt"]), ("⇧", ["shift"]),
  ("⌃", ["control", "ctrl"]), ("⇪", ["caps lock"]), ("↩", ["return", "enter"]),
  ("⌫", ["delete", "backspace"]), ("⌦", ["forward delete"]), ("⎋", ["escape", "esc"]),
  ("⇥", ["tab"]), ("→", ["right arrow"]), ("←", ["left arrow"]), ("↑", ["up arrow"]),
  ("↓", ["down arrow"]), ("✓", ["tick"]), ("×", ["times", "multiply"]), ("÷", ["divide"]),
  ("™", ["trademark", "tm"]), ("√", ["sqrt"]), ("≈", ["approximately"]), ("…", ["ellipsis"]),
]

private func symbolEntry(_ scalar: Unicode.Scalar, aliases: [String]) -> CharacterEntry? {
  guard let name = scalar.properties.name else { return nil }
  let code = String(format: "U+%04X", scalar.value)
  return CharacterEntry(
    id: "symbol:" + code, text: String(scalar),
    title: name.prefix(1) + name.dropFirst().lowercased(),
    subtitle: ([code] + aliases).joined(separator: " · "),
    names: [name] + [scalar.properties.nameAlias].compactMap(\.self) + aliases, keywords: [])
}

private func isSymbol(_ scalar: Unicode.Scalar) -> Bool {
  switch scalar.properties.generalCategory {
  case .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol, .connectorPunctuation,
    .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
    .finalPunctuation, .otherPunctuation, .otherNumber, .letterNumber, .spaceSeparator:
    true
  case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
    scalar.value < 0x0530 || (0x1D00..<0x2000).contains(scalar.value)
  default:
    false
  }
}

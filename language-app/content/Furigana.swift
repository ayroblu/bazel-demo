import Foundation

public struct FuriganaSegment: Equatable, Sendable {
  public let text: String
  public let reading: String?
  public let emphasized: Bool

  public init(text: String, reading: String? = nil, emphasized: Bool = false) {
    self.text = text
    self.reading = reading
    self.emphasized = emphasized
  }
}

/// A piece of a phrase that a line break may not split: a reading sits above `base`, and
/// `trailing` holds characters that Japanese line-break rules keep on the same line.
public struct FuriganaUnit: Equatable, Sendable {
  public let base: String
  public let reading: String?
  public let trailing: String
  public let emphasized: Bool

  public init(
    base: String, reading: String? = nil, trailing: String = "", emphasized: Bool = false
  ) {
    self.base = base
    self.reading = reading
    self.trailing = trailing
    self.emphasized = emphasized
  }

  public var text: String { base + trailing }
}

public enum FuriganaParser {
  public static func parse(_ source: String) -> [FuriganaSegment] {
    var segments: [FuriganaSegment] = []
    var plain = ""
    var base = ""
    var reading = ""
    var insideReading = false
    var emphasized = false

    func flushPlain() {
      if !plain.isEmpty {
        segments.append(FuriganaSegment(text: plain, emphasized: emphasized))
        plain = ""
      }
    }

    let characters = Array(source)
    var position = 0
    while position < characters.count {
      let character = characters[position]
      position += 1
      if character == "*", !insideReading, position < characters.count,
        characters[position] == "*"
      {
        position += 1
        flushPlain()
        emphasized.toggle()
      } else if character == "[", !insideReading {
        if let range = plain.range(of: #"[\p{Han}々〆ヵヶ]+$"#, options: .regularExpression) {
          base = String(plain[range])
          plain.removeSubrange(range)
          flushPlain()
          insideReading = true
        } else {
          plain.append(character)
        }
      } else if character == "]", insideReading {
        if !base.isEmpty, !reading.isEmpty {
          segments.append(FuriganaSegment(text: base, reading: reading, emphasized: emphasized))
        } else {
          plain += base + "[" + reading + "]"
        }
        base = ""
        reading = ""
        insideReading = false
      } else if insideReading {
        reading.append(character)
      } else {
        plain.append(character)
      }
    }

    if insideReading {
      plain += base + "[" + reading
    }
    flushPlain()
    return segments
  }

  /// Characters that may not open a line: small kana, the repeat and long vowel marks,
  /// closing brackets and trailing punctuation.
  private static let neverStartsALine = Set(
    "、。，．・：；？！ー々ゝゞぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮ）］｝〕〉》」』】〟’”,.:;?!")
  /// Characters that may not close a line, so the next character joins them.
  private static let neverEndsALine = Set("（［｛〔〈《「『【〝‘“")

  /// Splits a phrase into the units a line may break between. A kanji run keeps its reading,
  /// Japanese text breaks between characters, and Latin words stay whole.
  public static func breakableUnits(_ source: String) -> [FuriganaUnit] {
    var units: [FuriganaUnit] = []

    func appendToLast(_ character: Character) {
      guard let last = units.last else {
        units.append(FuriganaUnit(base: String(character)))
        return
      }
      units[units.count - 1] = FuriganaUnit(
        base: last.base,
        reading: last.reading,
        trailing: last.trailing + String(character),
        emphasized: last.emphasized
      )
    }

    for segment in parse(source) {
      let emphasized = segment.emphasized
      if let reading = segment.reading {
        units.append(
          FuriganaUnit(base: segment.text, reading: reading, emphasized: emphasized))
        continue
      }
      for character in segment.text {
        let last = units.last
        if let last, character.isWhitespace || neverStartsALine.contains(character)
          || closesWithOpener(last)
        {
          appendToLast(character)
        } else if let last, last.reading == nil, last.trailing.isEmpty,
          last.emphasized == emphasized, staysInTheSameWord(last.base, character)
        {
          units[units.count - 1] = FuriganaUnit(
            base: last.base + String(character), emphasized: emphasized)
        } else {
          units.append(FuriganaUnit(base: String(character), emphasized: emphasized))
        }
      }
    }
    return units
  }

  private static func closesWithOpener(_ unit: FuriganaUnit) -> Bool {
    guard let last = unit.trailing.last ?? unit.base.last else { return false }
    return neverEndsALine.contains(last)
  }

  /// Latin script has no break between letters, so a word is one unit.
  private static func staysInTheSameWord(_ base: String, _ next: Character) -> Bool {
    guard let previous = base.last else { return false }
    return !breaksBetweenCharacters(previous) && !breaksBetweenCharacters(next)
      && !previous.isWhitespace && !next.isWhitespace
  }

  /// Japanese wraps between characters; Latin script does not.
  private static func breaksBetweenCharacters(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
      (0x3000...0x30ff).contains(scalar.value)
        || (0x3400...0x4dbf).contains(scalar.value)
        || (0x4e00...0x9fff).contains(scalar.value)
        || (0xf900...0xfaff).contains(scalar.value)
        || (0xff00...0xff60).contains(scalar.value)
    }
  }

  public static func displayText(_ source: String) -> String {
    parse(source).map(\.text).joined()
  }

  public static func speechText(_ source: String) -> String {
    parse(source).map { $0.reading ?? $0.text }.joined()
  }
}

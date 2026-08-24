import Foundation

public enum Romaji {
  /// Particles keep their spoken sound rather than their spelling in Hepburn romaji.
  private static let particleReadings: [String: String] = ["は": "wa", "へ": "e", "を": "o"]

  /// Transliterates the kana readings of a furigana-annotated source into Hepburn romaji.
  /// Each furigana segment becomes a separate word, so kanji clusters read as units.
  /// Returns nil when the source contains nothing transliterable, such as Latin-script text.
  public static func transliterate(_ source: String) -> String? {
    let segments = FuriganaParser.parse(source)
    var words: [String] = []
    var previousHadReading = false

    for segment in segments {
      let kana = segment.reading ?? segment.text
      let trimmed = kana.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }
      if let particle = particleReadings[trimmed] {
        words.append(particle)
        previousHadReading = false
        continue
      }
      guard let latin = trimmed.applyingTransform(.toLatin, reverse: false) else { continue }
      let word = latin.trimmingCharacters(in: .whitespaces)
      guard !word.isEmpty, word != trimmed else { continue }
      // Kana that trails a kanji cluster is okurigana, so it stays part of that word.
      if segment.reading == nil, let previous = words.last, previousHadReading {
        words[words.count - 1] = previous + word
      } else {
        words.append(word)
      }
      previousHadReading = segment.reading != nil
    }

    return words.isEmpty ? nil : words.joined(separator: " ")
  }

  public static func isSupported(languageCode: String) -> Bool {
    languageCode.lowercased().hasPrefix("ja")
  }
}

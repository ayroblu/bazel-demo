import Foundation

public enum CSVDeckWriter {
  public static func encode(_ deck: Deck) -> String {
    var text = "\(field(deck.languageCode)),\(field(deck.answerColumnName))\n"
    for card in deck.cards {
      text += "\(field(card.prompt)),\(field(card.answer))\n"
    }
    return text
  }

  /// Quotes a field only when the CSV grammar needs it, keeping hand written decks readable.
  private static func field(_ value: String) -> String {
    guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
      return value
    }
    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
}

import Foundation

public struct DeckCard: Codable, Identifiable, Equatable, Sendable {
  public let id: String
  public let prompt: String
  public let answer: String
  public let languageCode: String

  public init(prompt: String, answer: String, languageCode: String) {
    self.id = Self.makeId(languageCode: languageCode, prompt: prompt, answer: answer)
    self.prompt = prompt
    self.answer = answer
    self.languageCode = languageCode
  }

  private static func makeId(languageCode: String, prompt: String, answer: String) -> String {
    Data("\(languageCode)\u{1f}\(prompt)\u{1f}\(answer)".utf8).base64EncodedString()
  }
}

public struct Deck: Equatable, Identifiable, Sendable {
  public var id: String { "\(languageCode):\(name)" }
  public let name: String
  public let languageCode: String
  public let answerColumnName: String
  public var cards: [DeckCard]
}

/// Anki's three queue counters: unseen cards, same-day step cards, and graduated cards.
public struct QueueCounts: Equatable, Sendable {
  public var new: Int
  public var learning: Int
  public var review: Int

  public init(new: Int = 0, learning: Int = 0, review: Int = 0) {
    self.new = new
    self.learning = learning
    self.review = review
  }
}

/// Per-day new-card budget, reset when the calendar day rolls over.
public struct DailyProgress: Codable, Equatable, Sendable {
  public var day: Date
  public var introduced: Int
  public var extraAllowance: Int

  public init(day: Date, introduced: Int = 0, extraAllowance: Int = 0) {
    self.day = day
    self.introduced = introduced
    self.extraAllowance = extraAllowance
  }
}

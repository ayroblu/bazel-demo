import Foundation

public struct DeckCard: Codable, Identifiable, Equatable, Sendable {
  public let id: String
  public let prompt: String
  public let answer: String
  public let languageCode: String

  public init(prompt: String, answer: String, languageCode: String) {
    self.id = Self.makeID(languageCode: languageCode, prompt: prompt, answer: answer)
    self.prompt = prompt
    self.answer = answer
    self.languageCode = languageCode
  }

  private static func makeID(languageCode: String, prompt: String, answer: String) -> String {
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

  public var total: Int { new + learning + review }
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

public enum CardRating: Int, CaseIterable, Sendable {
  case again = 1
  case hard = 2
  case good = 3
  case easy = 4

  var title: String {
    switch self {
    case .again: "Again"
    case .hard: "Hard"
    case .good: "Good"
    case .easy: "Easy"
    }
  }
}

public struct ReviewState: Codable, Equatable, Sendable {
  public var due: Date
  public var stability: Double
  public var difficulty: Double
  public var elapsedDays: Double
  /// Seconds until the card is next due; sub-day while the card walks learning steps.
  public var scheduledInterval: TimeInterval
  public var phase: LearningPhase
  /// Index into the learning or relearning steps for the current phase.
  public var step: Int
  public var reps: Int
  public var lapses: Int
  public var lastReview: Date?

  public init(
    due: Date = .distantPast,
    stability: Double = 0,
    difficulty: Double = 5,
    elapsedDays: Double = 0,
    scheduledInterval: TimeInterval = 0,
    phase: LearningPhase = .learning,
    step: Int = 0,
    reps: Int = 0,
    lapses: Int = 0,
    lastReview: Date? = nil
  ) {
    self.due = due
    self.stability = stability
    self.difficulty = difficulty
    self.elapsedDays = elapsedDays
    self.scheduledInterval = scheduledInterval
    self.phase = phase
    self.step = step
    self.reps = reps
    self.lapses = lapses
    self.lastReview = lastReview
  }
}

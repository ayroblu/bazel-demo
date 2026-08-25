import Foundation

public enum CardRating: Int, CaseIterable, Sendable {
  case again = 1
  case hard = 2
  case good = 3
  case easy = 4
}

/// Where a card sits in Anki's queue model: intra-day steps for new and lapsed cards,
/// day-scale intervals once the card has graduated.
public enum LearningPhase: String, Codable, Sendable {
  case learning
  case review
  case relearning
}

public struct ReviewState: Codable, Equatable, Sendable {
  public var due: Date
  public var stability: Double
  public var difficulty: Double
  /// Whole Anki days between the previous review and the one that produced this state.
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

import Foundation

/// FSRS-5 memory model combined with Anki's learning and relearning steps.
///
/// Anki does not let FSRS schedule same-day repetitions: new cards walk the fixed
/// learning steps (1m, 10m by default) and lapsed cards walk the relearning steps (10m),
/// while FSRS tracks stability and difficulty throughout and picks every interval of a
/// day or longer. Intervals are not fuzzed, so a given history always schedules the same way.
public enum FSRSScheduler {
  /// FSRS-5 default parameters published by the open-spaced-repetition project.
  private static let weights = [
    0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575,
    0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621,
  ]
  private static let requestedRetention = 0.9
  private static let factor = 19.0 / 81.0
  private static let decay = -0.5
  private static let day: TimeInterval = 86_400
  /// Anki's default maximum interval.
  public static let maximumIntervalDays = 36_500

  /// Anki's default deck preset steps.
  public static let learningSteps: [TimeInterval] = [60, 600]
  public static let relearningSteps: [TimeInterval] = [600]

  public static func review(
    _ previous: ReviewState?,
    rating: CardRating,
    now: Date = Date(),
    calendar: SchedulerCalendar = SchedulerCalendar()
  ) -> ReviewState {
    var state = previous ?? ReviewState()
    let isNew = state.reps == 0 || state.lastReview == nil
    let elapsedDays = state.lastReview.map { calendar.elapsedDays(from: $0, to: now) } ?? 0

    if isNew {
      state.stability = initialStability(rating)
      state.difficulty = initialDifficulty(rating)
    } else {
      // FSRS derives the new stability from the difficulty the card carried into the review,
      // so difficulty is updated afterwards.
      let difficulty = state.difficulty
      // Anki picks the short-term formula by the day boundary, not by the queue the card is in.
      state.stability =
        elapsedDays == 0
        ? shortTermStability(state.stability, rating: rating)
        : longTermStability(
          state.stability,
          difficulty: difficulty,
          rating: rating,
          elapsedDays: Double(elapsedDays)
        )
      state.difficulty = nextDifficulty(previous: difficulty, rating: rating)
    }

    // Anki counts a lapse only when a graduated card is forgotten.
    if rating == .again, state.phase == .review, !isNew {
      state.lapses += 1
    }

    let phase: LearningPhase = isNew ? .learning : state.phase
    let outcome = schedule(phase: phase, step: state.step, rating: rating, stability: state.stability)

    state.phase = outcome.phase
    state.step = outcome.step
    state.scheduledInterval = outcome.interval
    state.elapsedDays = Double(elapsedDays)
    state.reps += 1
    state.lastReview = now
    state.due = due(
      from: now,
      interval: outcome.interval,
      isDayScale: outcome.phase == .review,
      calendar: calendar
    )
    return state
  }

  public static func previewIntervals(
    for previous: ReviewState?,
    now: Date = Date(),
    calendar: SchedulerCalendar = SchedulerCalendar()
  ) -> [CardRating: TimeInterval] {
    Dictionary(
      uniqueKeysWithValues: CardRating.allCases.map { rating in
        (rating, review(previous, rating: rating, now: now, calendar: calendar).scheduledInterval)
      })
  }

  // MARK: - Step scheduling

  private struct Outcome {
    let phase: LearningPhase
    let step: Int
    let interval: TimeInterval
  }

  private static func schedule(
    phase: LearningPhase,
    step: Int,
    rating: CardRating,
    stability: Double
  ) -> Outcome {
    switch phase {
    case .review:
      guard rating == .again else {
        return Outcome(phase: .review, step: 0, interval: graduatedInterval(stability: stability))
      }
      guard let first = relearningSteps.first else {
        return Outcome(phase: .review, step: 0, interval: graduatedInterval(stability: stability))
      }
      return Outcome(phase: .relearning, step: 0, interval: first)
    case .learning:
      return stepOutcome(phase: .learning, steps: learningSteps, step: step, rating: rating, stability: stability)
    case .relearning:
      return stepOutcome(phase: .relearning, steps: relearningSteps, step: step, rating: rating, stability: stability)
    }
  }

  private static func stepOutcome(
    phase: LearningPhase,
    steps: [TimeInterval],
    step: Int,
    rating: CardRating,
    stability: Double
  ) -> Outcome {
    func graduate() -> Outcome {
      Outcome(phase: .review, step: 0, interval: graduatedInterval(stability: stability))
    }
    guard !steps.isEmpty else { return graduate() }
    let current = min(step, steps.count - 1)

    switch rating {
    case .again:
      return Outcome(phase: phase, step: 0, interval: steps[0])
    case .hard:
      // Anki delays Hard on the first step by the average of the first two steps.
      let delay = current == 0 && steps.count > 1 ? (steps[0] + steps[1]) / 2 : steps[current]
      return Outcome(phase: phase, step: current, interval: delay)
    case .good:
      let next = current + 1
      return next < steps.count
        ? Outcome(phase: phase, step: next, interval: steps[next])
        : graduate()
    case .easy:
      return graduate()
    }
  }

  /// Sub-day steps come due to the minute; a day scale interval comes due at the rollover
  /// that many days ahead, the way Anki stores due dates as day numbers.
  private static func due(
    from now: Date,
    interval: TimeInterval,
    isDayScale: Bool,
    calendar: SchedulerCalendar
  ) -> Date {
    guard isDayScale else { return now.addingTimeInterval(interval) }
    let days = max(1, Int((interval / day).rounded()))
    return calendar.startOfDay(byAdding: days, to: now)
  }

  // MARK: - FSRS memory model

  private static func initialStability(_ rating: CardRating) -> Double {
    max(0.1, weights[rating.rawValue - 1])
  }

  private static func initialDifficulty(_ rating: CardRating) -> Double {
    clamp(weights[4] - exp(weights[5] * Double(rating.rawValue - 1)) + 1, lower: 1, upper: 10)
  }

  private static func nextDifficulty(previous: Double, rating: CardRating) -> Double {
    let delta = -weights[6] * Double(rating.rawValue - 3)
    // FSRS-5 damps the change as difficulty approaches its maximum.
    let linear = previous + delta * (10 - previous) / 9
    let reverted = weights[7] * initialDifficulty(.easy) + (1 - weights[7]) * linear
    return clamp(reverted, lower: 1, upper: 10)
  }

  private static func retrievability(stability: Double, elapsedDays: Double) -> Double {
    pow(1 + factor * elapsedDays / max(stability, 0.01), decay)
  }

  private static func shortTermStability(_ stability: Double, rating: CardRating) -> Double {
    let updated = stability * exp(weights[17] * (Double(rating.rawValue) - 3 + weights[18]))
    return max(0.1, updated)
  }

  private static func longTermStability(
    _ stability: Double,
    difficulty: Double,
    rating: CardRating,
    elapsedDays: Double
  ) -> Double {
    let recall = retrievability(stability: stability, elapsedDays: elapsedDays)
    if rating == .again {
      let forgotten =
        weights[11]
        * pow(max(difficulty, 1), -weights[12])
        * (pow(stability + 1, weights[13]) - 1)
        * exp((1 - recall) * weights[14])
      // A lapse never raises stability.
      return clamp(min(forgotten, stability), lower: 0.1, upper: Double(maximumIntervalDays))
    }
    let hardPenalty = rating == .hard ? weights[15] : 1
    let easyBonus = rating == .easy ? weights[16] : 1
    let grown =
      stability
      * (1 + exp(weights[8])
        * (11 - difficulty)
        * pow(stability, -weights[9])
        * (exp((1 - recall) * weights[10]) - 1)
        * hardPenalty
        * easyBonus)
    return clamp(grown, lower: 0.1, upper: Double(maximumIntervalDays))
  }

  /// Interval that hits the requested retention, floored at Anki's one day minimum.
  private static func graduatedInterval(stability: Double) -> TimeInterval {
    let days = stability / factor * (pow(requestedRetention, 1 / decay) - 1)
    return Double(max(1, min(Int(days.rounded()), maximumIntervalDays))) * day
  }

  private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
  }
}

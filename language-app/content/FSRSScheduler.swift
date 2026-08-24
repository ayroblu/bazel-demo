import Foundation

public enum FSRSScheduler {
  // FSRS v4.5 weights published by the open-spaced-repetition project.
  private static let weights = [
    0.4, 0.6, 2.4, 5.8, 4.93, 0.94, 0.86, 0.01, 1.49,
    0.14, 0.94, 2.18, 0.05, 0.34, 1.26, 0.29, 2.61,
  ]
  private static let requestedRetention = 0.9
  private static let factor = 19.0 / 81.0
  private static let decay = -0.5

  public static func review(
    _ previous: ReviewState?,
    rating: CardRating,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> ReviewState {
    guard var state = previous, state.reps > 0, let lastReview = state.lastReview else {
      let stability = weights[rating.rawValue - 1]
      let difficulty = initialDifficulty(rating)
      let interval = intervalDays(stability: stability)
      return ReviewState(
        due: calendar.date(byAdding: .day, value: interval, to: now) ?? now,
        stability: stability,
        difficulty: difficulty,
        elapsedDays: 0,
        scheduledDays: interval,
        reps: 1,
        lapses: rating == .again ? 1 : 0,
        lastReview: now
      )
    }

    let elapsed = max(0, now.timeIntervalSince(lastReview) / 86_400)
    let retrievability = pow(1 + factor * elapsed / max(state.stability, 0.01), decay)
    let difficulty = nextDifficulty(previous: state.difficulty, rating: rating)
    let stability: Double
    if rating == .again {
      stability = max(
        0.1,
        weights[11]
          * pow(max(state.difficulty, 1), -weights[12])
          * (pow(state.stability + 1, weights[13]) - 1)
          * exp((1 - retrievability) * weights[14])
      )
      state.lapses += 1
    } else {
      let hardPenalty = rating == .hard ? weights[15] : 1
      let easyBonus = rating == .easy ? weights[16] : 1
      stability = state.stability * (
        1 + exp(weights[8])
          * (11 - difficulty)
          * pow(state.stability, -weights[9])
          * (exp((1 - retrievability) * weights[10]) - 1)
          * hardPenalty
          * easyBonus
      )
    }

    let interval = intervalDays(stability: stability)
    state.due = calendar.date(byAdding: .day, value: interval, to: now) ?? now
    state.stability = stability
    state.difficulty = difficulty
    state.elapsedDays = elapsed
    state.scheduledDays = interval
    state.reps += 1
    state.lastReview = now
    return state
  }

  public static func previewIntervals(
    for previous: ReviewState?,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [CardRating: Int] {
    Dictionary(uniqueKeysWithValues: CardRating.allCases.map { rating in
      (rating, review(previous, rating: rating, now: now, calendar: calendar).scheduledDays)
    })
  }

  private static func initialDifficulty(_ rating: CardRating) -> Double {
    clamp(weights[4] - exp(weights[5] * Double(rating.rawValue - 1)) + 1, lower: 1, upper: 10)
  }

  private static func nextDifficulty(previous: Double, rating: CardRating) -> Double {
    let delta = -weights[6] * Double(rating.rawValue - 3)
    let reverted = weights[7] * initialDifficulty(.easy) + (1 - weights[7]) * (previous + delta)
    return clamp(reverted, lower: 1, upper: 10)
  }

  private static func intervalDays(stability: Double) -> Int {
    let interval = stability / factor * (pow(requestedRetention, 1 / decay) - 1)
    return max(1, min(Int(interval.rounded()), 36_500))
  }

  private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
  }
}

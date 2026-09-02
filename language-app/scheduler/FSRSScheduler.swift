import Foundation

/// FSRS-6 memory model combined with Anki's learning and relearning steps.
///
/// Anki does not let FSRS schedule same-day repetitions: new cards walk the fixed
/// learning steps (1m, 10m by default) and lapsed cards walk the relearning steps (10m),
/// while FSRS tracks stability and difficulty throughout and picks every interval of a
/// day or longer. Passing a card always earns strictly more time than the button below it.
///
/// Intervals are fuzzed when a seed is supplied, which spreads cards that were introduced
/// together. The seed stands in for Anki's card id, so a card's fuzz can be previewed on the
/// answer buttons and then repeated exactly when the answer is graded. Told how many cards
/// each upcoming day already holds, the fuzz is steered towards the quieter days.
public enum FSRSScheduler {
  /// FSRS-6 default parameters published by the open-spaced-repetition project. The last one
  /// is the decay of the forgetting curve, which FSRS-5 held fixed at 0.5.
  private static let weights = [
    0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796,
    1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
  ]
  private static let requestedRetention = 0.9
  private static let decay = -weights[20]
  private static let factor = exp(log(0.9) / decay) - 1
  private static let minimumStability = 0.001
  private static let maximumStability = 36_500.0
  private static let day: TimeInterval = 86_400
  /// Anki's default maximum interval.
  public static let maximumIntervalDays = 36_500

  /// Anki's default deck preset steps.
  private static let learningSteps: [TimeInterval] = [60, 600]
  private static let relearningSteps: [TimeInterval] = [600]

  public static func review(
    _ previous: ReviewState?,
    rating: CardRating,
    now: Date = Date(),
    calendar: SchedulerCalendar = SchedulerCalendar(),
    fuzzSeed: UInt64? = nil,
    cardsDueIn: ((Int) -> Int)? = nil
  ) -> ReviewState {
    let prior = previous ?? ReviewState()
    let isNew = prior.reps == 0 || prior.lastReview == nil
    let elapsedDays = prior.lastReview.map { calendar.elapsedDays(from: $0, to: now) } ?? 0
    let spread = Spread(factor: fuzzFactor(seed: fuzzSeed), workload: cardsDueIn)

    func stability(_ rating: CardRating) -> Double {
      guard !isNew else { return initialStability(rating) }
      // Anki picks the short-term formula by the day boundary, not by the queue the card is in.
      return elapsedDays == 0
        ? shortTermStability(prior.stability, rating: rating)
        : longTermStability(
          prior.stability,
          difficulty: prior.difficulty,
          rating: rating,
          elapsedDays: Double(elapsedDays)
        )
    }

    let phase: LearningPhase = isNew ? .learning : prior.phase
    let outcome = schedule(
      phase: phase,
      step: prior.step,
      rating: rating,
      spread: spread,
      previousDays: phase == .review ? Int((prior.scheduledInterval / day).rounded()) : 0,
      intervalDays: { graduatedDays(stability: stability($0)) }
    )

    var state = prior
    state.stability = stability(rating)
    // FSRS derives the new stability from the difficulty the card carried into the review,
    // so difficulty is updated afterwards.
    state.difficulty =
      isNew ? initialDifficulty(rating) : nextDifficulty(previous: prior.difficulty, rating: rating)
    // Anki counts a lapse only when a graduated card is forgotten.
    if rating == .again, prior.phase == .review, !isNew {
      state.lapses += 1
    }
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
      spread: spread,
      calendar: calendar
    )
    return state
  }

  /// Anki seeds fuzz with the card's id and its review count, so every preview of an answer
  /// matches the interval that grading it will produce, and rescheduling never drifts.
  public static func fuzzSeed(cardId: String, reps: Int) -> UInt64 {
    hash(cardId: cardId, salt: reps)
  }

  /// FNV-1a, the hash Anki shuffles tied cards with.
  public static func hash(cardId: String, salt: Int) -> UInt64 {
    var value: UInt64 = 0xCBF2_9CE4_8422_2325
    func mix(_ byte: UInt8) {
      value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
    }
    for byte in cardId.utf8 { mix(byte) }
    let bits = UInt64(bitPattern: Int64(salt))
    for shift in stride(from: 0, through: 56, by: 8) { mix(UInt8((bits >> UInt64(shift)) & 0xFF)) }
    return value
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
    spread: Spread,
    previousDays: Int,
    intervalDays: (CardRating) -> Double
  ) -> Outcome {
    func passing() -> Outcome {
      let interval = passingInterval(
        rating: rating,
        spread: spread,
        previousDays: previousDays,
        intervalDays: intervalDays
      )
      return Outcome(phase: .review, step: 0, interval: interval)
    }
    switch phase {
    case .review:
      guard rating == .again, let first = relearningSteps.first else { return passing() }
      return Outcome(phase: .relearning, step: 0, interval: first)
    case .learning:
      return stepOutcome(
        phase: .learning, steps: learningSteps, step: step, rating: rating, spread: spread,
        intervalDays: intervalDays)
    case .relearning:
      return stepOutcome(
        phase: .relearning, steps: relearningSteps, step: step, rating: rating, spread: spread,
        intervalDays: intervalDays)
    }
  }

  private static func stepOutcome(
    phase: LearningPhase,
    steps: [TimeInterval],
    step: Int,
    rating: CardRating,
    spread: Spread,
    intervalDays: (CardRating) -> Double
  ) -> Outcome {
    func graduate() -> Outcome {
      let interval = graduatingInterval(rating: rating, spread: spread, intervalDays: intervalDays)
      return Outcome(phase: .review, step: 0, interval: interval)
    }
    guard !steps.isEmpty else { return graduate() }
    let current = min(step, steps.count - 1)

    switch rating {
    case .again:
      return Outcome(phase: phase, step: 0, interval: steps[0])
    case .hard:
      // Anki delays Hard on the first step by the average of the first two steps, or by half
      // as much again as the only step, so that Hard never equals Again.
      let first = steps.count > 1 ? (steps[0] + steps[1]) / 2 : min(steps[0] * 1.5, steps[0] + day)
      return Outcome(phase: phase, step: current, interval: current == 0 ? first : steps[current])
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
    spread: Spread,
    calendar: SchedulerCalendar
  ) -> Date {
    guard isDayScale else { return now.addingTimeInterval(fuzzedStep(interval, spread: spread)) }
    let days = max(1, Int((interval / day).rounded()))
    return calendar.startOfDay(byAdding: days, to: now)
  }

  // MARK: - Day scale intervals

  /// The buttons a passing review offers, each of which has to beat the one below it, so a
  /// harder answer can never buy more time than an easier one once the intervals are rounded.
  private static func passingInterval(
    rating: CardRating,
    spread: Spread,
    previousDays: Int,
    intervalDays: (CardRating) -> Double
  ) -> TimeInterval {
    func constrained(_ rating: CardRating, atLeast minimum: Int) -> Int {
      let days = intervalDays(rating)
      let floor = max(
        minimumReviewFuzzInterval(days, previousDays: previousDays), minimum)
      return withReviewFuzz(days, spread: spread, minimum: floor)
    }
    let hard = constrained(.hard, atLeast: 1)
    if rating == .hard { return Double(hard) * day }
    let good = constrained(.good, atLeast: hard + 1)
    if rating == .good { return Double(good) * day }
    return Double(constrained(.easy, atLeast: good + 1)) * day
  }

  /// Anki rounds a graduating interval before fuzzing it, and still keeps Easy above Good.
  private static func graduatingInterval(
    rating: CardRating,
    spread: Spread,
    intervalDays: (CardRating) -> Double
  ) -> TimeInterval {
    let good = withReviewFuzz(max(intervalDays(.good).rounded(), 1), spread: spread, minimum: 1)
    guard rating == .easy else { return Double(good) * day }
    let easy = withReviewFuzz(max(intervalDays(.easy).rounded(), 1), spread: spread, minimum: good + 1)
    return Double(easy) * day
  }

  /// Interval that hits the requested retention, in days and before any rounding.
  private static func graduatedDays(stability: Double) -> Double {
    stability / factor * (pow(requestedRetention, 1 / decay) - 1)
  }

  // MARK: - Fuzz and load balancing

  /// How a day scale interval is picked out of the range fuzz allows: at random from the
  /// seed, and, when the days already booked are known, weighted towards the quieter ones.
  private struct Spread {
    let factor: Double?
    let workload: ((Int) -> Int)?
  }

  /// The day ranges Anki fuzzes by, and how much of each range it adds to the one day it
  /// always spreads a review over.
  private static let fuzzRanges: [(start: Double, end: Double, factor: Double)] = [
    (2.5, 7, 0.15), (7, 20, 0.1), (20, .greatestFiniteMagnitude, 0.05),
  ]

  /// Anki stops balancing beyond this interval, where an extra day either way is noise.
  private static let maximumBalancedInterval = 90

  private static func fuzzFactor(seed: UInt64?) -> Double? {
    guard let seed else { return nil }
    var z = seed &+ 0x9E37_79B9_7F4A_7C15
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return Double((z ^ (z >> 31)) >> 11) * 0x1p-53
  }

  /// Anki adds up to a quarter of a learning step, and never more than five minutes, to the
  /// time the card comes due. The step itself is reported unfuzzed on the answer buttons.
  private static func fuzzedStep(_ interval: TimeInterval, spread: Spread) -> TimeInterval {
    guard let factor = spread.factor else { return interval }
    let range = min(interval * 0.25, 300).rounded(.down)
    return interval + (range * factor).rounded(.down)
  }

  private static func withReviewFuzz(_ days: Double, spread: Spread, minimum: Int) -> Int {
    guard let factor = spread.factor else {
      return clamp(Int(days.rounded()), lower: minimum, upper: maximumIntervalDays)
    }
    if let balanced = balancedDay(days, factor: factor, minimum: minimum, spread: spread) {
      return balanced
    }
    let (lower, upper) = fuzzBounds(days, minimum: minimum)
    return Int((Double(lower) + factor * Double(1 + upper - lower)).rounded(.down))
  }

  /// Anki's load balancer. Every day the fuzz range allows is weighted by how much work is
  /// already booked on it, `(1 / cards)^2.15 * (1 / days)^3`, so a card lands on a quiet day
  /// and, all else being equal, the earlier one. A day with nothing on it always wins.
  private static func balancedDay(
    _ days: Double,
    factor: Double,
    minimum: Int,
    spread: Spread
  ) -> Int? {
    guard let workload = spread.workload,
      Int(days) <= maximumBalancedInterval,
      minimum <= maximumBalancedInterval
    else { return nil }
    let (lower, upper) = fuzzBounds(days, minimum: minimum)
    guard lower < upper else { return lower }

    let weights = (lower...upper).map { target -> Double in
      let booked = workload(target)
      guard booked > 0 else { return 1 }
      return pow(1 / Double(booked), 2.15) * pow(1 / Double(target), 3)
    }
    let total = weights.reduce(0, +)
    guard total > 0 else { return nil }

    var remaining = factor * total
    for (offset, weight) in weights.enumerated() {
      remaining -= weight
      if remaining < 0 { return lower + offset }
    }
    return upper
  }

  /// Short intervals are not fuzzed at all; longer ones spread by a day plus a share of each
  /// range they reach into.
  private static func fuzzBounds(_ days: Double, minimum: Int) -> (Int, Int) {
    let minimum = min(minimum, maximumIntervalDays)
    let days = min(max(days, Double(minimum)), Double(maximumIntervalDays))
    let delta =
      days < 2.5
      ? 0
      : fuzzRanges.reduce(1.0) { $0 + $1.factor * max(min(days, $1.end) - $1.start, 0) }
    var lower = clamp(Int((days - delta).rounded()), lower: minimum, upper: maximumIntervalDays)
    var upper = clamp(Int((days + delta).rounded()), lower: minimum, upper: maximumIntervalDays)
    if upper == lower, upper > 2, upper < maximumIntervalDays {
      upper = lower + 1
    }
    if lower > upper { lower = upper }
    return (lower, upper)
  }

  /// Fuzz may push an interval below the one the card already had, so Anki floors it: an
  /// interval that grew must stay above the old one, and one that shrank is left alone.
  private static func minimumReviewFuzzInterval(_ days: Double, previousDays: Int) -> Int {
    let (_, upper) = fuzzBounds(days, minimum: 1)
    if Int(days.rounded()) > previousDays { return previousDays + 1 }
    return previousDays <= upper ? previousDays : 0
  }

  private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
    min(max(value, lower), upper)
  }

  // MARK: - FSRS memory model

  private static func initialStability(_ rating: CardRating) -> Double {
    clamp(weights[rating.rawValue - 1], lower: minimumStability, upper: maximumStability)
  }

  private static func initialDifficulty(_ rating: CardRating) -> Double {
    clamp(weights[4] - exp(weights[5] * Double(rating.rawValue - 1)) + 1, lower: 1, upper: 10)
  }

  private static func nextDifficulty(previous: Double, rating: CardRating) -> Double {
    let delta = -weights[6] * Double(rating.rawValue - 3)
    // FSRS damps the change as difficulty approaches its maximum.
    let damped = previous + delta * (10 - previous) / 9
    let reverted = weights[7] * (initialDifficulty(.easy) - damped) + damped
    return clamp(reverted, lower: 1, upper: 10)
  }

  private static func retrievability(stability: Double, elapsedDays: Double) -> Double {
    pow(1 + factor * elapsedDays / max(stability, minimumStability), decay)
  }

  /// FSRS-6 lets a same-day repeat lower stability only when the card was forgotten.
  private static func shortTermStability(_ stability: Double, rating: CardRating) -> Double {
    let change =
      exp(weights[17] * (Double(rating.rawValue) - 3 + weights[18]))
      * pow(max(stability, minimumStability), -weights[19])
    let updated = stability * (rating == .again ? change : max(change, 1))
    return clamp(updated, lower: minimumStability, upper: maximumStability)
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
      // A lapse always costs at least as much stability as one same-day failure.
      let ceiling = stability / exp(weights[17] * weights[18])
      return clamp(min(forgotten, ceiling), lower: minimumStability, upper: maximumStability)
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
    return clamp(grown, lower: minimumStability, upper: maximumStability)
  }

  private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
  }
}

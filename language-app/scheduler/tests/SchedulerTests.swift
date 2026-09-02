import Foundation
import Testing
@testable import LanguageScheduler

// MARK: - Fixtures

/// A fixed UTC calendar keeps every expectation deterministic, whatever the machine is set to.
private let utc: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  return calendar
}()

private let anki = SchedulerCalendar(rolloverHour: 4, calendar: utc)

private func at(_ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
  utc.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
}

private let day: TimeInterval = 86_400

private func review(
  _ previous: ReviewState?,
  _ rating: CardRating,
  _ now: Date
) -> ReviewState {
  FSRSScheduler.review(previous, rating: rating, now: now, calendar: anki)
}

private func days(_ state: ReviewState) -> Double {
  state.scheduledInterval / day
}

/// The published FSRS-6 defaults, restated here so the tests judge the implementation
/// against the reference formulas rather than against themselves.
private enum Reference {
  static let w = [
    0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796,
    1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
  ]
  static let decay = -w[20]
  static let factor = exp(log(0.9) / decay) - 1

  static func retrievability(stability: Double, elapsedDays: Double) -> Double {
    pow(1 + factor * elapsedDays / stability, decay)
  }

  static func initialDifficulty(_ rating: CardRating) -> Double {
    min(max(w[4] - exp(w[5] * Double(rating.rawValue - 1)) + 1, 1), 10)
  }

  static func nextDifficulty(_ difficulty: Double, _ rating: CardRating) -> Double {
    let delta = -w[6] * Double(rating.rawValue - 3)
    let damped = difficulty + delta * (10 - difficulty) / 9
    return min(max(w[7] * (initialDifficulty(.easy) - damped) + damped, 1), 10)
  }

  /// Stability after a successful review a day or more later.
  static func recallStability(
    stability: Double,
    difficulty: Double,
    rating: CardRating,
    elapsedDays: Double
  ) -> Double {
    let recall = retrievability(stability: stability, elapsedDays: elapsedDays)
    let hardPenalty = rating == .hard ? w[15] : 1
    let easyBonus = rating == .easy ? w[16] : 1
    return stability
      * (1 + exp(w[8]) * (11 - difficulty) * pow(stability, -w[9])
        * (exp((1 - recall) * w[10]) - 1) * hardPenalty * easyBonus)
  }

  static func forgetStability(
    stability: Double,
    difficulty: Double,
    elapsedDays: Double
  ) -> Double {
    let recall = retrievability(stability: stability, elapsedDays: elapsedDays)
    let forgotten =
      w[11] * pow(difficulty, -w[12]) * (pow(stability + 1, w[13]) - 1)
      * exp((1 - recall) * w[14])
    return min(forgotten, stability / exp(w[17] * w[18]))
  }

  /// A day of fuzz plus a share of every range the interval reaches into.
  static func fuzzDelta(_ interval: Double) -> Double {
    guard interval >= 2.5 else { return 0 }
    let ranges: [(Double, Double, Double)] = [
      (2.5, 7, 0.15), (7, 20, 0.1), (20, .greatestFiniteMagnitude, 0.05),
    ]
    return ranges.reduce(1.0) { $0 + $1.2 * max(min(interval, $1.1) - $1.0, 0) }
  }

  static func shortTermStability(stability: Double, rating: CardRating) -> Double {
    let change = exp(w[17] * (Double(rating.rawValue) - 3 + w[18])) * pow(stability, -w[19])
    return stability * (rating == .again ? change : max(change, 1))
  }
}

private func expectClose(_ actual: Double, _ expected: Double, tolerance: Double = 1e-9) {
  #expect(abs(actual - expected) <= tolerance, "\(actual) is not within \(tolerance) of \(expected)")
}

// MARK: - Day boundaries

@Test func theDayBoundaryDefaultsToFourInTheMorning() {
  #expect(SchedulerCalendar.defaultRolloverHour == 4)
  #expect(SchedulerCalendar().rolloverHour == 4)
  #expect(SchedulerCalendar().calendar == Calendar.current)

  // Every default path through the scheduler uses that boundary.
  let byDefault = SchedulerCalendar(calendar: utc)
  #expect(byDefault.rolloverHour == 4)
  #expect(byDefault.startOfDay(for: at(10, 3, 59)) == at(9, 4))
  #expect(byDefault.startOfDay(for: at(10, 4)) == at(10, 4))
  #expect(byDefault.elapsedDays(from: at(10, 23), to: at(11, 3)) == 0)

  // An hour outside the day clamps instead of silently shifting the boundary.
  #expect(SchedulerCalendar(rolloverHour: 30).rolloverHour == 23)
  #expect(SchedulerCalendar(rolloverHour: -5).rolloverHour == 0)
}

@Test func dayBoundariesFollowTheRolloverHour() {
  // 03:59 still belongs to the previous Anki day; 04:00 opens the next one.
  #expect(anki.startOfDay(for: at(10, 3, 59)) == at(9, 4))
  #expect(anki.startOfDay(for: at(10, 4)) == at(10, 4))
  #expect(anki.startOfDay(for: at(10, 23, 30)) == at(10, 4))
  #expect(anki.endOfDay(for: at(10, 23, 30)) == at(11, 4))

  // Elapsed days count day boundaries crossed, not hours.
  #expect(anki.elapsedDays(from: at(10, 5), to: at(10, 23)) == 0)
  #expect(anki.elapsedDays(from: at(10, 23), to: at(11, 3)) == 0)
  #expect(anki.elapsedDays(from: at(10, 23), to: at(11, 5)) == 1)
  #expect(anki.elapsedDays(from: at(10, 5), to: at(20, 5)) == 10)
  // Reviewing before the previous review never yields negative days.
  #expect(anki.elapsedDays(from: at(20, 5), to: at(10, 5)) == 0)
}

// MARK: - The four buttons on a new card

@Test func newCardRespondsToEachButton() {
  let now = at(10)

  let again = review(nil, .again, now)
  #expect(again.phase == .learning)
  #expect(again.step == 0)
  #expect(again.scheduledInterval == 60)
  #expect(again.due == now.addingTimeInterval(60))
  #expect(again.reps == 1)
  // A card that was never graduated cannot lapse.
  #expect(again.lapses == 0)

  let hard = review(nil, .hard, now)
  #expect(hard.phase == .learning)
  #expect(hard.step == 0)
  // Anki delays Hard on the first step by the average of the first two steps.
  #expect(hard.scheduledInterval == 330)

  let good = review(nil, .good, now)
  #expect(good.phase == .learning)
  #expect(good.step == 1)
  #expect(good.scheduledInterval == 600)

  let easy = review(nil, .easy, now)
  #expect(easy.phase == .review)
  #expect(easy.step == 0)
  #expect(days(easy) >= 1)
  // Day scale cards come due at a rollover, the way Anki stores due dates as day numbers.
  #expect(easy.due == anki.startOfDay(byAdding: Int(days(easy)), to: now))

  // Initial memory state comes straight from the FSRS defaults.
  expectClose(again.stability, Reference.w[0])
  expectClose(hard.stability, Reference.w[1])
  expectClose(good.stability, Reference.w[2])
  expectClose(easy.stability, Reference.w[3])
  for rating in CardRating.allCases {
    expectClose(review(nil, rating, now).difficulty, Reference.initialDifficulty(rating))
  }
  #expect(again.difficulty > hard.difficulty)
  #expect(hard.difficulty > good.difficulty)
  #expect(good.difficulty > easy.difficulty)
}

@Test func learningStepsWalkForwardsAndBackwards() {
  let start = at(10)
  let firstStep = review(nil, .good, start)
  #expect(firstStep.step == 1)

  // Again drops back to the first step.
  let relapsed = review(firstStep, .again, start.addingTimeInterval(600))
  #expect(relapsed.phase == .learning)
  #expect(relapsed.step == 0)
  #expect(relapsed.scheduledInterval == 60)
  #expect(relapsed.lapses == 0)

  // Hard repeats the step the card is on.
  let repeated = review(firstStep, .hard, start.addingTimeInterval(600))
  #expect(repeated.step == 1)
  #expect(repeated.scheduledInterval == 600)
  #expect(repeated.phase == .learning)

  // Good off the last step graduates, Easy graduates from anywhere.
  let graduated = review(firstStep, .good, start.addingTimeInterval(600))
  #expect(graduated.phase == .review)
  #expect(days(graduated) >= 1)
  #expect(review(relapsed, .easy, start.addingTimeInterval(900)).phase == .review)
}

// MARK: - Same day versus a later day

@Test func sameDayRepeatsUseTheShortTermFormulaWhateverTheHour() {
  let first = review(nil, .good, at(10, 9))

  let tenMinutes = review(first, .good, at(10, 9, 10))
  let sameEvening = review(first, .good, at(10, 23))
  let beforeRollover = review(first, .good, at(11, 3, 30))

  // The short-term update depends only on the grade, so every same-day hour agrees.
  #expect(tenMinutes.elapsedDays == 0)
  #expect(sameEvening.elapsedDays == 0)
  #expect(beforeRollover.elapsedDays == 0)
  expectClose(tenMinutes.stability, sameEvening.stability)
  expectClose(tenMinutes.stability, beforeRollover.stability)
  expectClose(
    tenMinutes.stability,
    Reference.shortTermStability(stability: first.stability, rating: .good)
  )
}

@Test func aLearningCardReviewedTheNextDayUsesTheLongTermFormula() {
  let first = review(nil, .good, at(10, 9))
  let sameDay = review(first, .good, at(10, 23))
  let nextDay = review(first, .good, at(11, 9))

  #expect(nextDay.elapsedDays == 1)
  // Crossing the rollover switches formulas, so the two outcomes must differ.
  #expect(abs(nextDay.stability - sameDay.stability) > 1e-6)
  expectClose(
    nextDay.stability,
    Reference.recallStability(
      stability: first.stability,
      difficulty: first.difficulty,
      rating: .good,
      elapsedDays: 1
    )
  )
}

@Test func stabilityIsDerivedFromTheDifficultyTheCardCarriedIntoTheReview() {
  // A review ten days after the card was last seen, so the long term formula applies.
  let previous = ReviewState(
    due: at(20),
    stability: 10,
    difficulty: 5,
    phase: .review,
    reps: 3,
    lastReview: at(10)
  )

  for rating in [CardRating.hard, .good, .easy] {
    let state = review(previous, rating, at(20))
    expectClose(
      state.stability,
      Reference.recallStability(
        stability: 10,
        difficulty: 5,
        rating: rating,
        elapsedDays: 10
      )
    )
    expectClose(state.difficulty, Reference.nextDifficulty(5, rating))
  }

  let lapsed = review(previous, .again, at(20))
  expectClose(
    lapsed.stability,
    Reference.forgetStability(stability: 10, difficulty: 5, elapsedDays: 10)
  )
  expectClose(lapsed.difficulty, Reference.nextDifficulty(5, .again))
}

// MARK: - Missed days

@Test func lateReviewsEarnMoreStabilityThanOnTimeOnes() {
  let graduated = review(review(nil, .good, at(1)), .good, at(1, 10, 10))
  #expect(graduated.phase == .review)
  let interval = Int(days(graduated))

  let onTime = review(graduated, .good, anki.startOfDay(byAdding: interval, to: at(1)))
  let late = review(graduated, .good, anki.startOfDay(byAdding: interval + 20, to: at(1)))
  let veryLate = review(graduated, .good, anki.startOfDay(byAdding: interval + 200, to: at(1)))

  #expect(onTime.elapsedDays < late.elapsedDays)
  #expect(late.stability > onTime.stability)
  #expect(veryLate.stability > late.stability)
  #expect(days(veryLate) > days(onTime))
}

@Test func skippingADueDateDoesNotCorruptTheSchedule() {
  var state = review(review(nil, .good, at(1)), .good, at(1, 10, 10))
  var lastInterval = days(state)

  // The reader disappears for a month, comes back, then keeps up for several reviews.
  state = review(state, .good, anki.startOfDay(byAdding: 30, to: state.due))
  #expect(state.elapsedDays >= 30)
  #expect(days(state) > lastInterval)
  lastInterval = days(state)

  for _ in 1...5 {
    state = review(state, .good, state.due)
    #expect(days(state) > lastInterval)
    #expect(state.difficulty >= 1 && state.difficulty <= 10)
    #expect(state.stability.isFinite)
    lastInterval = days(state)
  }
}

// MARK: - Lapses

@Test func forgettingAGraduatedCardEntersRelearningAndCountsOneLapse() {
  let graduated = review(review(nil, .good, at(1)), .good, at(1, 10, 10))
  let lapseTime = graduated.due

  let lapsed = review(graduated, .again, lapseTime)
  #expect(lapsed.phase == .relearning)
  #expect(lapsed.scheduledInterval == 600)
  #expect(lapsed.due == lapseTime.addingTimeInterval(600))
  #expect(lapsed.lapses == 1)
  #expect(lapsed.stability <= graduated.stability)
  #expect(lapsed.difficulty > graduated.difficulty)

  // Failing again while relearning is not a second lapse.
  let failedAgain = review(lapsed, .again, lapseTime.addingTimeInterval(600))
  #expect(failedAgain.lapses == 1)
  #expect(failedAgain.phase == .relearning)
  #expect(failedAgain.scheduledInterval == 600)

  // Good leaves relearning for a day scale interval, and the lapse count stays put.
  let recovered = review(failedAgain, .good, lapseTime.addingTimeInterval(1_200))
  #expect(recovered.phase == .review)
  #expect(days(recovered) >= 1)
  #expect(recovered.lapses == 1)

  // Forgetting it again later counts the second lapse.
  let secondLapse = review(recovered, .again, recovered.due)
  #expect(secondLapse.lapses == 2)
}

@Test func hardOnTheOnlyRelearningStepWaitsHalfAsLongAgain() {
  let graduated = review(review(nil, .good, at(1)), .good, at(1, 10, 10))
  let lapsed = review(graduated, .again, graduated.due)

  // With a single 10m step, Anki spaces Hard at 15m so it is never equal to Again.
  let hard = review(lapsed, .hard, lapsed.due)
  #expect(hard.phase == .relearning)
  #expect(hard.scheduledInterval == 900)
  #expect(review(lapsed, .again, lapsed.due).scheduledInterval == 600)
}

@Test func passingASameDayRepeatNeverLowersStability() {
  let first = review(nil, .easy, at(10, 9))
  for rating in [CardRating.hard, .good, .easy] {
    #expect(review(first, rating, at(10, 10)).stability >= first.stability)
  }
  // Failing one still may.
  #expect(review(first, .again, at(10, 10)).stability < first.stability)
}

// MARK: - Multi-day runs

@Test func aRunOfGoodsGrowsIntervalsAndAlwaysComesDueAtARollover() {
  var state = review(review(nil, .good, at(1)), .good, at(1, 10, 10))
  var previousInterval = days(state)
  var previousStability = state.stability

  for _ in 1...10 {
    let reviewedAt = state.due
    let expectedElapsed = anki.elapsedDays(from: state.lastReview!, to: reviewedAt)
    state = review(state, .good, reviewedAt)

    #expect(state.phase == .review)
    #expect(Double(expectedElapsed) == state.elapsedDays)
    #expect(days(state) > previousInterval)
    #expect(state.stability > previousStability)
    #expect(state.due == anki.startOfDay(byAdding: Int(days(state)), to: reviewedAt))
    #expect(utc.component(.hour, from: state.due) == 4)
    previousInterval = days(state)
    previousStability = state.stability
  }
}

@Test func theIntervalOfAGraduatedCardTracksItsStability() {
  // At 90% requested retention the FSRS interval in days is the stability, rounded.
  var state = review(nil, .easy, at(1))
  for step in 1...6 {
    #expect(days(state) == Double(min(max(1, Int(state.stability.rounded())), 36_500)))
    state = review(state, step.isMultiple(of: 2) ? .good : .easy, state.due)
  }
}

@Test func ratingsAreOrderedOnceTheCardHasGraduated() {
  let graduated = review(review(nil, .good, at(1)), .good, at(1, 10, 10))
  let intervals = Dictionary(
    uniqueKeysWithValues: CardRating.allCases.map { rating in
      (rating, review(graduated, rating, graduated.due).scheduledInterval)
    })

  // Again sends the card back to a ten minute step, so it is always the shortest.
  #expect(intervals[.again] == 600)
  #expect(intervals[.hard]! < intervals[.good]!)
  #expect(intervals[.good]! < intervals[.easy]!)
}

@Test func difficultyClimbsWithLapsesAndFallsWithEasyReviews() {
  var hardest = review(nil, .again, at(1))
  var day = 2
  for _ in 1...12 {
    hardest = review(hardest, .again, at(day))
    day += 1
    #expect(hardest.difficulty <= 10)
    // FSRS-6 floors stability at 0.001 days.
    #expect(hardest.stability >= 0.001)
  }
  #expect(hardest.difficulty > 8)

  var easiest = review(nil, .again, at(1))
  var easyDay = 2
  for _ in 1...12 {
    easiest = review(easiest, .easy, at(easyDay))
    easyDay += 1
    #expect(easiest.difficulty >= 1)
  }
  #expect(easiest.difficulty < 2)
  #expect(easiest.stability > hardest.stability)
}

@Test func longHistoriesStayInsideAnkiLimits() {
  var state = review(nil, .easy, at(1))
  for _ in 1...40 {
    state = review(state, .easy, state.due)
    #expect(state.stability.isFinite)
    #expect(state.scheduledInterval.isFinite)
    #expect(days(state) <= Double(FSRSScheduler.maximumIntervalDays))
    #expect(state.difficulty >= 1 && state.difficulty <= 10)
  }
  #expect(days(state) == Double(FSRSScheduler.maximumIntervalDays))
  #expect(state.due > state.lastReview!)
}

// MARK: - Fuzz

private func fuzzed(
  _ previous: ReviewState?,
  _ rating: CardRating,
  _ now: Date,
  seed: UInt64
) -> ReviewState {
  FSRSScheduler.review(previous, rating: rating, now: now, calendar: anki, fuzzSeed: seed)
}

@Test func fuzzSpreadsIntervalsWithoutStrayingFromTheOneFsrsAsksFor() {
  let graduated = review(review(nil, .good, at(1)), .good, at(1, 10, 10))
  let plain = review(graduated, .good, graduated.due)
  let allowed = Reference.fuzzDelta(days(plain)) + 1

  var intervals: Set<Double> = []
  for seed in UInt64(1)...50 {
    let state = fuzzed(graduated, .good, graduated.due, seed: seed)
    intervals.insert(days(state))
    #expect(abs(days(state) - days(plain)) <= allowed)
    #expect(days(state) >= 1)
    // Fuzz moves the interval, never the memory the card is judged by.
    expectClose(state.stability, plain.stability)
    expectClose(state.difficulty, plain.difficulty)
    #expect(state.due == anki.startOfDay(byAdding: Int(days(state)), to: graduated.due))
  }
  #expect(intervals.count > 1)
}

@Test func aCardsFuzzIsFixedByItsIdAndReviewCount() {
  let seed = FSRSScheduler.fuzzSeed(cardId: "猫[ねこ]", reps: 2)
  #expect(fuzzed(nil, .easy, at(1), seed: seed) == fuzzed(nil, .easy, at(1), seed: seed))
  #expect(FSRSScheduler.fuzzSeed(cardId: "犬[いぬ]", reps: 2) != seed)
  #expect(FSRSScheduler.fuzzSeed(cardId: "猫[ねこ]", reps: 3) != seed)
}

@Test func learningStepsComeDueALittleLateWhileReportingThePlainDelay() {
  var offsets: Set<TimeInterval> = []
  for seed in UInt64(1)...50 {
    let state = fuzzed(nil, .again, at(1), seed: seed)
    // Anki fuzzes when the step comes due, but shows the step itself on the button.
    #expect(state.scheduledInterval == 60)
    let offset = state.due.timeIntervalSince(at(1))
    #expect(offset >= 60 && offset < 75)
    offsets.insert(offset)
  }
  #expect(offsets.count > 1)
}

@Test func passingButtonsStayInOrderWhateverTheFuzz() {
  let graduated = review(review(nil, .good, at(1)), .good, at(1, 10, 10))
  for seed in UInt64(1)...50 {
    let intervals = CardRating.allCases.map {
      fuzzed(graduated, $0, graduated.due, seed: seed).scheduledInterval
    }
    #expect(intervals[0] == 600)
    #expect(intervals[1] < intervals[2])
    #expect(intervals[2] < intervals[3])
  }
}

@Test func fuzzNeverPullsAGrowingIntervalBelowTheOldOne() {
  var state = review(review(nil, .good, at(1)), .good, at(1, 10, 10))
  for seed in UInt64(1)...30 {
    let previous = days(state)
    state = fuzzed(state, .good, state.due, seed: seed)
    // Growth only stops at Anki's maximum interval.
    #expect(days(state) > previous || previous == Double(FSRSScheduler.maximumIntervalDays))
  }
}

// MARK: - Load balancing

private func balanced(
  _ previous: ReviewState?,
  _ rating: CardRating,
  _ now: Date,
  seed: UInt64,
  booked: @escaping (Int) -> Int
) -> ReviewState {
  FSRSScheduler.review(
    previous, rating: rating, now: now, calendar: anki, fuzzSeed: seed, cardsDueIn: booked)
}

@Test func aQuietDayInTheFuzzRangeTakesTheCard() throws {
  let graduated = review(review(nil, .good, at(1)), .good, at(1, 10, 10))
  let plain = review(graduated, .easy, graduated.due)
  let target = Int(days(plain))
  // Every day of the range is buried under work except the earliest one.
  let quiet = target - 1

  for seed in UInt64(1)...50 {
    let state = balanced(graduated, .easy, graduated.due, seed: seed) { $0 == quiet ? 0 : 500 }
    #expect(Int(days(state)) == quiet)
  }
}

@Test func balancingPrefersTheLighterOfTwoDays() {
  let graduated = review(review(nil, .good, at(1)), .good, at(1, 10, 10))
  let plain = review(graduated, .easy, graduated.due)
  let target = Int(days(plain))

  var chosen: [Int: Int] = [:]
  for seed in UInt64(1)...200 {
    let state = balanced(graduated, .easy, graduated.due, seed: seed) {
      $0 == target ? 40 : 4
    }
    chosen[Int(days(state)), default: 0] += 1
  }
  // The heavily booked day is not banned, just unlikely.
  #expect(chosen[target, default: 0] * 4 < chosen.values.reduce(0, +))
  #expect(chosen.count > 1)
}

@Test func farOutIntervalsAreLeftToPlainFuzz() {
  var state = review(nil, .easy, at(1))
  while days(state) <= 90 {
    state = review(state, .easy, state.due)
  }
  for seed in UInt64(1)...20 {
    let unbalanced = fuzzed(state, .good, state.due, seed: seed)
    let attempted = balanced(state, .good, state.due, seed: seed) { _ in 500 }
    #expect(days(attempted) == days(unbalanced))
  }
}

@Test func reviewingIsAPureFunctionOfStateRatingAndTime() {
  let state = review(review(nil, .good, at(1)), .good, at(1, 10, 10))
  let first = review(state, .good, at(5))
  let second = review(state, .good, at(5))
  #expect(first == second)
  // Nothing about the input state is mutated by grading it.
  #expect(state.reps == 2)
}

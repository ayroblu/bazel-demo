import Foundation
import LanguageScheduler
import Observation

@MainActor
@Observable
public final class StudyStore {
  public private(set) var deck: Deck?
  public private(set) var reviewStates: [String: ReviewState] = [:]
  public private(set) var showingAnswer = false

  public static let defaultNewCardsPerDay = 20
  public static let defaultReviewsPerDay = 200
  /// Multiplier on the system's default speech rate.
  public static let defaultSpeechRate = 1.0
  public static let speechRateRange = 0.5...2.0

  private let defaults: UserDefaults
  private let calendar: SchedulerCalendar

  /// Drives the due-card queue; intra-day steps need re-evaluation while the deck is open.
  private var clock = Date()
  private var daily: DailyProgress

  private struct GradeUndo {
    let cardId: String
    let reviewState: ReviewState?
    let daily: DailyProgress
    let clock: Date
  }

  private static let undoLimit = 30
  private var undoStack: [GradeUndo] = []
  /// The card on screen. It is chosen when a card is asked for and never changes under the
  /// reader, so the queue is only consulted between cards.
  private var currentCardId: String?

  private static let keyPrefixes = [
    "language-app.review-states.v3.",
    "language-app.daily.v1.",
    "language-app.new-per-day.v1.",
    "language-app.speech-rate.v1.",
    "language-app.browse-repeats.v1.",
    "language-app.reviews-per-day.v1.",
  ]

  private var deckId: String { deck?.id ?? "unknown" }
  private var persistenceKey: String { Self.keyPrefixes[0] + deckId }
  private var dailyKey: String { Self.keyPrefixes[1] + deckId }
  private var limitKey: String { Self.keyPrefixes[2] + deckId }
  private var rateKey: String { Self.keyPrefixes[3] + deckId }
  private var browseRepeatsKey: String { Self.keyPrefixes[4] + deckId }
  private var reviewLimitKey: String { Self.keyPrefixes[5] + deckId }

  /// How many unseen cards enter the queue each day, Anki's new-card limit.
  public var newCardsPerDay: Int {
    didSet {
      let clamped = max(0, newCardsPerDay)
      guard clamped == newCardsPerDay else {
        newCardsPerDay = clamped
        return
      }
      defaults.set(clamped, forKey: limitKey)
    }
  }

  /// How many cards the day's queue may hold, Anki's review limit. New cards spend it too.
  public var reviewsPerDay: Int {
    didSet {
      let clamped = max(0, reviewsPerDay)
      guard clamped == reviewsPerDay else {
        reviewsPerDay = clamped
        return
      }
      defaults.set(clamped, forKey: reviewLimitKey)
    }
  }

  /// How fast this deck's prompts are spoken, as a multiple of the system's default rate.
  public var speechRate: Double {
    didSet {
      let clamped = min(max(speechRate, Self.speechRateRange.lowerBound), Self.speechRateRange.upperBound)
      guard clamped == speechRate else {
        speechRate = clamped
        return
      }
      defaults.set(clamped, forKey: rateKey)
    }
  }

  /// How many times browse auto play reads the question before revealing the answer.
  public var browseQuestionRepeats: Int {
    didSet {
      let clamped = min(
        max(browseQuestionRepeats, AutoBrowse.questionRepeatsRange.lowerBound),
        AutoBrowse.questionRepeatsRange.upperBound
      )
      guard clamped == browseQuestionRepeats else {
        browseQuestionRepeats = clamped
        return
      }
      defaults.set(clamped, forKey: browseRepeatsKey)
    }
  }

  public init(
    deck: Deck,
    defaults: UserDefaults = .standard,
    calendar: SchedulerCalendar = SchedulerCalendar()
  ) {
    let key = Self.keyPrefixes[2] + deck.id
    newCardsPerDay = max(0, defaults.object(forKey: key) as? Int ?? Self.defaultNewCardsPerDay)
    let storedReviewLimit = defaults.object(forKey: Self.keyPrefixes[5] + deck.id) as? Int
    reviewsPerDay = max(0, storedReviewLimit ?? Self.defaultReviewsPerDay)
    let storedRate = defaults.object(forKey: Self.keyPrefixes[3] + deck.id) as? Double
    speechRate = min(
      max(storedRate ?? Self.defaultSpeechRate, Self.speechRateRange.lowerBound),
      Self.speechRateRange.upperBound
    )
    let storedRepeats = defaults.object(forKey: Self.keyPrefixes[4] + deck.id) as? Int
    browseQuestionRepeats = min(
      max(storedRepeats ?? AutoBrowse.defaultQuestionRepeats, AutoBrowse.questionRepeatsRange.lowerBound),
      AutoBrowse.questionRepeatsRange.upperBound
    )
    daily = DailyProgress(day: calendar.startOfDay(for: Date()))
    self.defaults = defaults
    self.calendar = calendar
    self.deck = deck
    loadProgress()
    loadDaily()
    currentCardId = queuedCard()?.id
  }

  /// Anki spends one review limit on every card the day serves, new ones included.
  public var reviewsRemainingToday: Int {
    max(0, reviewsPerDay - daily.reviewed - daily.introduced)
  }

  /// Anki gathers reviews first, so new cards only get what the review limit has left over.
  public var newCardsRemainingToday: Int {
    min(
      max(0, newCardsPerDay + daily.extraAllowance - daily.introduced),
      max(0, reviewsRemainingToday - dueReviewCards.count)
    )
  }

  public var extraCardsToday: Int { daily.extraAllowance }

  private var unseenCards: [DeckCard] {
    deck?.cards.filter { reviewStates[$0.id] == nil } ?? []
  }

  private func dueCards(matching phases: Set<LearningPhase>, shuffleTies: Bool) -> [DeckCard] {
    guard let deck else { return [] }
    return deck.cards.enumerated()
      .compactMap { position, card -> (card: DeckCard, due: Date, tie: UInt64)? in
        guard let state = reviewStates[card.id], phases.contains(state.phase), state.due <= clock
        else { return nil }
        // Anki breaks a tie on the due day by hashing the card, so cards that came due
        // together are not asked in the same order every day.
        let tie =
          shuffleTies
          ? FSRSScheduler.hash(
            cardId: card.id, salt: Int(state.lastReview?.timeIntervalSince1970 ?? 0))
          : UInt64(position)
        return (card, state.due, tie)
      }
      .sorted { ($0.due, $0.tie) < ($1.due, $1.tie) }
      .map(\.card)
  }

  private var dueReviewCards: [DeckCard] {
    Array(dueCards(matching: [.review], shuffleTies: true).prefix(reviewsRemainingToday))
  }

  /// Cards waiting right now, in Anki's order: a learning step that has come due is shown
  /// ahead of everything, then reviews with today's new cards spread evenly through them.
  public var dueCards: [DeckCard] {
    dueCards(matching: [.learning, .relearning], shuffleTies: false)
      + Self.interspersed(dueReviewCards, Array(unseenCards.prefix(newCardsRemainingToday)))
  }

  /// Anki's intersperser, which spreads the shorter list evenly through the longer one.
  private static func interspersed(_ one: [DeckCard], _ two: [DeckCard]) -> [DeckCard] {
    let ratio = Double(one.count + 1) / Double(two.count + 1)
    var mixed: [DeckCard] = []
    mixed.reserveCapacity(one.count + two.count)
    var oneIndex = 0
    var twoIndex = 0
    while oneIndex < one.count || twoIndex < two.count {
      let takeTwo =
        oneIndex == one.count
        || (twoIndex < two.count && Double(twoIndex + 1) * ratio < Double(oneIndex + 1))
      if takeTwo {
        mixed.append(two[twoIndex])
        twoIndex += 1
      } else {
        mixed.append(one[oneIndex])
        oneIndex += 1
      }
    }
    return mixed
  }

  public var currentCard: DeckCard? {
    guard let currentCardId else { return nil }
    return deck?.cards.first { $0.id == currentCardId }
  }

  /// Anki's learn-ahead limit: with nothing else waiting, a learning step due this soon is
  /// shown early rather than making the reader wait for it.
  public static let learnAheadLimit: TimeInterval = 20 * 60

  private func queuedCard() -> DeckCard? {
    if let card = dueCards.first { return card }
    guard let deck else { return nil }
    let horizon = clock.addingTimeInterval(Self.learnAheadLimit)
    return
      deck.cards
      .compactMap { card -> (DeckCard, Date)? in
        guard let state = reviewStates[card.id], state.phase != .review, state.due <= horizon
        else { return nil }
        return (card, state.due)
      }
      .min { $0.1 < $1.1 }
      .map(\.0)
  }

  public var canUndo: Bool { !undoStack.isEmpty }

  public var counts: QueueCounts {
    guard let deck else { return QueueCounts() }
    let endOfDay = calendar.endOfDay(for: clock)
    var counts = QueueCounts(
      new: min(newCardsRemainingToday, unseenCards.count),
      review: dueReviewCards.count
    )
    for card in deck.cards {
      guard let state = reviewStates[card.id] else { continue }
      if state.phase != .review, state.due < endOfDay { counts.learning += 1 }
    }
    return counts
  }

  public var nextDueDate: Date? {
    guard let deck else { return nil }
    return deck.cards.compactMap { reviewStates[$0.id]?.due }.min()
  }

  /// True once nothing is left for today while unseen cards are still held back by the limit.
  public var isDayComplete: Bool {
    guard !unseenCards.isEmpty, dueCards.isEmpty else { return false }
    let endOfDay = calendar.endOfDay(for: clock)
    guard let next = nextDueDate else { return true }
    return next >= endOfDay
  }

  public func previewInterval(for rating: CardRating, now: Date = Date()) -> TimeInterval {
    guard let card = currentCard else { return 0 }
    return FSRSScheduler.review(
      reviewStates[card.id],
      rating: rating,
      now: now,
      calendar: calendar,
      fuzzSeed: fuzzSeed(for: card),
      cardsDueIn: upcomingWorkload(excluding: card, now: now)
    ).scheduledInterval
  }

  /// Ties fuzz to the card, so the interval on the button is the one the card gets.
  private func fuzzSeed(for card: DeckCard) -> UInt64 {
    FSRSScheduler.fuzzSeed(cardId: card.id, reps: reviewStates[card.id]?.reps ?? 0)
  }

  /// How many cards each upcoming day already holds, which lets the scheduler put this one
  /// on a quieter day. Only graduated cards are counted; steps are gone within the day.
  private func upcomingWorkload(excluding card: DeckCard, now: Date) -> (Int) -> Int {
    var booked: [Date: Int] = [:]
    for (id, state) in reviewStates where id != card.id && state.phase == .review {
      booked[calendar.startOfDay(for: state.due), default: 0] += 1
    }
    let calendar = calendar
    return { days in booked[calendar.startOfDay(byAdding: days, to: now), default: 0] }
  }

  public func revealAnswer() {
    showingAnswer = true
  }

  public func hideAnswer() {
    showingAnswer = false
  }

  /// Reads the clock and takes the next card from the queue. The only place the queue is
  /// consulted, so nothing moves while a card is on screen.
  public func advanceToNextCard(now: Date = Date()) {
    clock = now
    rolloverIfNeeded(now: now)
    currentCardId = queuedCard()?.id
    showingAnswer = false
  }

  /// Releases more unseen cards for today only; tomorrow returns to the daily limit.
  public func addExtraCardsToday(_ count: Int, now: Date = Date()) {
    guard count > 0 else { return }
    rolloverIfNeeded(now: now)
    daily.extraAllowance += count
    saveDaily()
    advanceToNextCard(now: now)
  }

  public func grade(_ rating: CardRating, now: Date = Date()) {
    guard let card = currentCard else { return }
    let isFirstSight = reviewStates[card.id] == nil
    let wasReview = reviewStates[card.id]?.phase == .review
    undoStack.append(
      GradeUndo(cardId: card.id, reviewState: reviewStates[card.id], daily: daily, clock: clock))
    if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
    rolloverIfNeeded(now: now)
    reviewStates[card.id] = FSRSScheduler.review(
      reviewStates[card.id],
      rating: rating,
      now: now,
      calendar: calendar,
      fuzzSeed: fuzzSeed(for: card),
      cardsDueIn: upcomingWorkload(excluding: card, now: now)
    )
    if isFirstSight {
      daily.introduced += 1
      saveDaily()
    } else if wasReview {
      // Only answers given to a graduated card spend the review limit; walking a learning
      // or relearning step does not.
      daily.reviewed += 1
      saveDaily()
    }
    saveProgress()
    advanceToNextCard(now: now)
  }

  /// Reverts the last grade and shows that card again on its answer, like Anki's undo.
  public func undo() {
    guard let entry = undoStack.popLast() else { return }
    if let state = entry.reviewState {
      reviewStates[entry.cardId] = state
    } else {
      reviewStates.removeValue(forKey: entry.cardId)
    }
    daily = entry.daily
    clock = entry.clock
    currentCardId = entry.cardId
    showingAnswer = true
    saveProgress()
    saveDaily()
  }

  public func isStudied(_ card: DeckCard) -> Bool {
    reviewStates[card.id] != nil
  }

  /// Takes an edited deck. A card's identity comes from its text, so progress for cards that
  /// were removed or rewritten is dropped rather than left stranded.
  public func updateDeck(_ deck: Deck) {
    self.deck = deck
    undoStack = []
    let live = Set(deck.cards.map(\.id))
    let kept = reviewStates.filter { live.contains($0.key) }
    if kept.count != reviewStates.count {
      reviewStates = kept
      saveProgress()
    }
    advanceToNextCard()
  }

  /// Every key this store writes, so a deleted deck leaves nothing behind.
  public static func removeStoredData(deckId: String, from defaults: UserDefaults) {
    for prefix in keyPrefixes {
      defaults.removeObject(forKey: prefix + deckId)
    }
  }

  public func resetProgress() {
    reviewStates = [:]
    undoStack = []
    daily = DailyProgress(day: calendar.startOfDay(for: clock))
    defaults.removeObject(forKey: persistenceKey)
    defaults.removeObject(forKey: dailyKey)
    advanceToNextCard(now: clock)
  }

  private func rolloverIfNeeded(now: Date) {
    let today = calendar.startOfDay(for: now)
    guard today != daily.day else { return }
    daily = DailyProgress(day: today)
    saveDaily()
  }

  private func loadProgress() {
    guard let data = defaults.data(forKey: persistenceKey) else { return }
    do {
      reviewStates = try JSONDecoder().decode([String: ReviewState].self, from: data)
    } catch {
      reviewStates = [:]
    }
  }

  private func saveProgress() {
    guard let data = try? JSONEncoder().encode(reviewStates) else { return }
    defaults.set(data, forKey: persistenceKey)
  }

  private func loadDaily() {
    guard let data = defaults.data(forKey: dailyKey),
      let stored = try? JSONDecoder().decode(DailyProgress.self, from: data)
    else { return }
    daily = stored
    rolloverIfNeeded(now: clock)
  }

  private func saveDaily() {
    guard let data = try? JSONEncoder().encode(daily) else { return }
    defaults.set(data, forKey: dailyKey)
  }
}

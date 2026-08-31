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
  /// Set by undo so the restored card is shown again regardless of queue order.
  private var pinnedCardId: String?

  private static let keyPrefixes = [
    "language-app.review-states.v3.",
    "language-app.daily.v1.",
    "language-app.new-per-day.v1.",
    "language-app.speech-rate.v1.",
    "language-app.browse-repeats.v1.",
  ]

  private var deckId: String { deck?.id ?? "unknown" }
  private var persistenceKey: String { Self.keyPrefixes[0] + deckId }
  private var dailyKey: String { Self.keyPrefixes[1] + deckId }
  private var limitKey: String { Self.keyPrefixes[2] + deckId }
  private var rateKey: String { Self.keyPrefixes[3] + deckId }
  private var browseRepeatsKey: String { Self.keyPrefixes[4] + deckId }

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
  }

  public var newCardsRemainingToday: Int {
    max(0, newCardsPerDay + daily.extraAllowance - daily.introduced)
  }

  public var extraCardsToday: Int { daily.extraAllowance }

  private var unseenCards: [DeckCard] {
    deck?.cards.filter { reviewStates[$0.id] == nil } ?? []
  }

  private var seenDueCards: [DeckCard] {
    guard let deck else { return [] }
    return deck.cards
      .compactMap { card -> (DeckCard, Date)? in
        guard let due = reviewStates[card.id]?.due, due <= clock else { return nil }
        return (card, due)
      }
      .sorted { $0.1 < $1.1 }
      .map(\.0)
  }

  /// Cards waiting right now: everything already due, then today's remaining new cards.
  public var dueCards: [DeckCard] {
    seenDueCards + unseenCards.prefix(newCardsRemainingToday)
  }

  public var currentCard: DeckCard? {
    if let pinnedCardId, let card = deck?.cards.first(where: { $0.id == pinnedCardId }) {
      return card
    }
    return dueCards.first
  }

  public var canUndo: Bool { !undoStack.isEmpty }

  public var counts: QueueCounts {
    guard let deck else { return QueueCounts() }
    let endOfDay = calendar.endOfDay(for: clock)
    var counts = QueueCounts(new: min(newCardsRemainingToday, unseenCards.count))
    for card in deck.cards {
      guard let state = reviewStates[card.id] else { continue }
      switch state.phase {
      case .learning, .relearning:
        if state.due < endOfDay { counts.learning += 1 }
      case .review:
        if state.due <= clock { counts.review += 1 }
      }
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
      calendar: calendar
    ).scheduledInterval
  }

  public func revealAnswer() {
    showingAnswer = true
  }

  public func hideAnswer() {
    showingAnswer = false
  }

  /// Re-evaluates the queue so cards waiting on a learning step come back when they are due.
  public func advanceClock(to date: Date = Date()) {
    clock = date
    rolloverIfNeeded(now: date)
  }

  /// Releases more unseen cards for today only; tomorrow returns to the daily limit.
  public func addExtraCardsToday(_ count: Int, now: Date = Date()) {
    guard count > 0 else { return }
    rolloverIfNeeded(now: now)
    daily.extraAllowance += count
    saveDaily()
  }

  public func grade(_ rating: CardRating, now: Date = Date()) {
    guard let card = currentCard else { return }
    let isFirstSight = reviewStates[card.id] == nil
    undoStack.append(
      GradeUndo(cardId: card.id, reviewState: reviewStates[card.id], daily: daily, clock: clock))
    if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
    pinnedCardId = nil
    rolloverIfNeeded(now: now)
    reviewStates[card.id] = FSRSScheduler.review(
      reviewStates[card.id],
      rating: rating,
      now: now,
      calendar: calendar
    )
    if isFirstSight {
      daily.introduced += 1
      saveDaily()
    }
    clock = now
    showingAnswer = false
    saveProgress()
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
    pinnedCardId = entry.cardId
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
    showingAnswer = false
    undoStack = []
    pinnedCardId = nil
    let live = Set(deck.cards.map(\.id))
    let kept = reviewStates.filter { live.contains($0.key) }
    guard kept.count != reviewStates.count else { return }
    reviewStates = kept
    saveProgress()
  }

  /// Every key this store writes, so a deleted deck leaves nothing behind.
  public static func removeStoredData(deckId: String, from defaults: UserDefaults) {
    for prefix in keyPrefixes {
      defaults.removeObject(forKey: prefix + deckId)
    }
  }

  public func resetProgress() {
    reviewStates = [:]
    showingAnswer = false
    undoStack = []
    pinnedCardId = nil
    daily = DailyProgress(day: calendar.startOfDay(for: clock))
    defaults.removeObject(forKey: persistenceKey)
    defaults.removeObject(forKey: dailyKey)
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

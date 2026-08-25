import Foundation
import Observation

@MainActor
@Observable
public final class StudyStore {
  public private(set) var deck: Deck?
  public private(set) var reviewStates: [String: ReviewState] = [:]
  public private(set) var errorMessage: String?
  public var showingAnswer = false

  public static let defaultNewCardsPerDay = 20
  /// Multiplier on the system's default speech rate.
  public static let defaultSpeechRate = 1.0
  public static let speechRateRange = 0.5...2.0

  private let defaults: UserDefaults
  private let calendar: Calendar

  /// Drives the due-card queue; intra-day steps need re-evaluation while the deck is open.
  public private(set) var clock = Date()
  private var daily: DailyProgress

  private var persistenceKey: String {
    "language-app.review-states.v3.\(deck?.id ?? "unknown")"
  }

  private var dailyKey: String {
    "language-app.daily.v1.\(deck?.id ?? "unknown")"
  }

  private var limitKey: String {
    "language-app.new-per-day.v1.\(deck?.id ?? "unknown")"
  }

  private var rateKey: String {
    "language-app.speech-rate.v1.\(deck?.id ?? "unknown")"
  }

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

  public init(deck: Deck, defaults: UserDefaults = .standard, calendar: Calendar = .current) {
    let key = "language-app.new-per-day.v1.\(deck.id)"
    newCardsPerDay = max(0, defaults.object(forKey: key) as? Int ?? Self.defaultNewCardsPerDay)
    let storedRate = defaults.object(forKey: "language-app.speech-rate.v1.\(deck.id)") as? Double
    speechRate = min(
      max(storedRate ?? Self.defaultSpeechRate, Self.speechRateRange.lowerBound),
      Self.speechRateRange.upperBound
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

  public var currentCard: DeckCard? { dueCards.first }

  public var counts: QueueCounts {
    guard let deck else { return QueueCounts() }
    let endOfDay = calendar.startOfDay(for: clock).addingTimeInterval(86_400)
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
    let endOfDay = calendar.startOfDay(for: clock).addingTimeInterval(86_400)
    guard let next = nextDueDate else { return true }
    return next >= endOfDay
  }

  public func previewInterval(for rating: CardRating, now: Date = Date()) -> TimeInterval {
    guard let card = currentCard else { return 0 }
    return FSRSScheduler.review(reviewStates[card.id], rating: rating, now: now).scheduledInterval
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
    rolloverIfNeeded(now: now)
    reviewStates[card.id] = FSRSScheduler.review(reviewStates[card.id], rating: rating, now: now)
    if isFirstSight {
      daily.introduced += 1
      saveDaily()
    }
    clock = now
    showingAnswer = false
    saveProgress()
  }

  public func isStudied(_ card: DeckCard) -> Bool {
    reviewStates[card.id] != nil
  }

  /// Takes an edited deck. A card's identity comes from its text, so progress for cards that
  /// were removed or rewritten is dropped rather than left stranded.
  public func updateDeck(_ deck: Deck) {
    self.deck = deck
    showingAnswer = false
    let live = Set(deck.cards.map(\.id))
    let kept = reviewStates.filter { live.contains($0.key) }
    guard kept.count != reviewStates.count else { return }
    reviewStates = kept
    saveProgress()
  }

  public func resetProgress() {
    reviewStates = [:]
    showingAnswer = false
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
      errorMessage = "Saved review progress could not be read."
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

import Foundation
import Observation

@MainActor
@Observable
public final class StudyStore {
  public private(set) var deck: Deck?
  public private(set) var reviewStates: [String: ReviewState] = [:]
  public private(set) var errorMessage: String?
  public var showingAnswer = false

  private let defaults: UserDefaults

  /// Drives the due-card queue; intra-day steps need re-evaluation while the deck is open.
  public private(set) var clock = Date()

  private var persistenceKey: String {
    "language-app.review-states.v3.\(deck?.id ?? "unknown")"
  }

  public init(deck: Deck, defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.deck = deck
    loadProgress()
  }

  public var dueCards: [DeckCard] {
    guard let deck else { return [] }
    let now = clock
    return deck.cards
      .filter { reviewStates[$0.id]?.due ?? .distantPast <= now }
      .sorted { left, right in
        (reviewStates[left.id]?.due ?? .distantPast) < (reviewStates[right.id]?.due ?? .distantPast)
      }
  }

  public var currentCard: DeckCard? { dueCards.first }

  public var nextDueDate: Date? {
    guard let deck else { return nil }
    return deck.cards.compactMap { reviewStates[$0.id]?.due }.min()
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
  }

  public func grade(_ rating: CardRating, now: Date = Date()) {
    guard let card = currentCard else { return }
    reviewStates[card.id] = FSRSScheduler.review(reviewStates[card.id], rating: rating, now: now)
    clock = now
    showingAnswer = false
    saveProgress()
  }

  public func resetProgress() {
    reviewStates = [:]
    showingAnswer = false
    defaults.removeObject(forKey: persistenceKey)
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
}

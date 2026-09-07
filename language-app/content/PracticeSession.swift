import Foundation
import LanguageScheduler
import Observation

/// An extra pass over cards already studied. It schedules every card from scratch, so ratings
/// walk the learning steps inside the session and never touch the deck's saved progress.
@MainActor
@Observable
public final class PracticeSession {
  public let cards: [DeckCard]
  public private(set) var showingAnswer = false

  private struct Undo {
    let cardId: String
    let state: ReviewState?
    let queue: [String]
    let clock: Date
  }

  private let calendar: SchedulerCalendar
  private var states: [String: ReviewState] = [:]
  private var queue: [String]
  private var clock: Date
  private var undoStack: [Undo] = []

  public init(
    cards: [DeckCard],
    now: Date = Date(),
    calendar: SchedulerCalendar = SchedulerCalendar()
  ) {
    self.cards = cards
    self.calendar = calendar
    clock = now
    queue = cards.map(\.id)
  }

  public var currentCard: DeckCard? {
    guard let id = queue.first else { return nil }
    return cards.first { $0.id == id }
  }

  /// Cards still to answer, counting a card that came back on a learning step once.
  public var remaining: Int { queue.count }

  public var isComplete: Bool { queue.isEmpty }

  public var canUndo: Bool { !undoStack.isEmpty }

  public func revealAnswer() {
    showingAnswer = true
  }

  public func previewInterval(for rating: CardRating) -> TimeInterval {
    guard let card = currentCard else { return 0 }
    return FSRSScheduler.review(
      states[card.id], rating: rating, now: clock, calendar: calendar
    ).scheduledInterval
  }

  /// Grades the card on screen. A card that graduates leaves the session; one still on a
  /// learning step goes to the back of the queue.
  public func grade(_ rating: CardRating, now: Date = Date()) {
    guard let card = currentCard else { return }
    undoStack.append(Undo(cardId: card.id, state: states[card.id], queue: queue, clock: clock))
    clock = now
    let state = FSRSScheduler.review(states[card.id], rating: rating, now: now, calendar: calendar)
    states[card.id] = state
    queue.removeFirst()
    if state.phase != .review { queue.append(card.id) }
    showingAnswer = false
  }

  /// Puts the last graded card back on screen with its answer showing.
  public func undo() {
    guard let entry = undoStack.popLast() else { return }
    states[entry.cardId] = entry.state
    queue = entry.queue
    clock = entry.clock
    showingAnswer = true
  }
}

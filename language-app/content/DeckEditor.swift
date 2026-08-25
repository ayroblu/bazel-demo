import Foundation

/// Card edits allowed on a deck. A card's identity is its text, so a studied card cannot be
/// rewritten, moved or removed without throwing its schedule away; those cards are locked.
public struct DeckEditor {
  public enum Failure: LocalizedError, Equatable {
    case locked
    case duplicate
    case empty

    public var errorDescription: String? {
      switch self {
      case .locked:
        "Studied cards are locked. Reset the deck's progress to change them."
      case .duplicate: "Another card in this deck already has that text."
      case .empty: "A card needs a prompt and an answer."
      }
    }
  }

  public let deck: Deck
  private let locked: (DeckCard) -> Bool

  public init(deck: Deck, isLocked: @escaping (DeckCard) -> Bool) {
    self.deck = deck
    locked = isLocked
  }

  public func isLocked(_ card: DeckCard) -> Bool { locked(card) }

  public var lockedCount: Int { deck.cards.filter(locked).count }

  /// Studied cards keep their place: their position only ever fed the new-card queue they left.
  public func move(from source: IndexSet, to destination: Int) throws -> Deck {
    guard source.allSatisfy({ !locked(deck.cards[$0]) }) else { throw Failure.locked }
    var updated = deck
    updated.cards.move(fromOffsets: source, toOffset: destination)
    return updated
  }

  public func shift(from index: Int, by offset: Int) throws -> Deck {
    let target = index + offset
    guard deck.cards.indices.contains(index), deck.cards.indices.contains(target) else {
      return deck
    }
    guard !locked(deck.cards[index]) else { throw Failure.locked }
    var updated = deck
    let card = updated.cards.remove(at: index)
    updated.cards.insert(card, at: target)
    return updated
  }

  public func remove(at offsets: IndexSet) throws -> Deck {
    guard offsets.allSatisfy({ !locked(deck.cards[$0]) }) else { throw Failure.locked }
    var updated = deck
    updated.cards.remove(atOffsets: offsets)
    return updated
  }

  public func append(prompt: String, answer: String) throws -> Deck {
    let card = try makeCard(prompt: prompt, answer: answer)
    guard !deck.cards.contains(where: { $0.id == card.id }) else { throw Failure.duplicate }
    var updated = deck
    updated.cards.append(card)
    return updated
  }

  public func replace(_ card: DeckCard, prompt: String, answer: String) throws -> Deck {
    guard let index = deck.cards.firstIndex(of: card) else { return deck }
    guard !locked(card) else { throw Failure.locked }
    let replacement = try makeCard(prompt: prompt, answer: answer)
    guard !deck.cards.contains(where: { $0.id == replacement.id && $0.id != card.id }) else {
      throw Failure.duplicate
    }
    var updated = deck
    updated.cards[index] = replacement
    return updated
  }

  private func makeCard(prompt: String, answer: String) throws -> DeckCard {
    let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty, !answer.isEmpty else { throw Failure.empty }
    return DeckCard(prompt: prompt, answer: answer, languageCode: deck.languageCode)
  }
}

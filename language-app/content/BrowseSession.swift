public struct BrowseSession: Equatable, Sendable {
  public let cards: [DeckCard]
  public private(set) var index: Int
  public private(set) var showingAnswer: Bool

  public init(cards: [DeckCard], shuffled: Bool = false) {
    self.cards = shuffled ? cards.shuffled() : cards
    index = 0
    showingAnswer = false
  }

  public init(cards: [DeckCard], using generator: inout some RandomNumberGenerator) {
    self.cards = cards.shuffled(using: &generator)
    index = 0
    showingAnswer = false
  }

  public var card: DeckCard? {
    cards.indices.contains(index) ? cards[index] : nil
  }

  public var canGoForward: Bool {
    card != nil && (!showingAnswer || index + 1 < cards.count)
  }

  public var canGoBack: Bool {
    showingAnswer || index > 0
  }

  public mutating func forward() {
    if showingAnswer {
      guard index + 1 < cards.count else { return }
      index += 1
      showingAnswer = false
    } else {
      showingAnswer = true
    }
  }

  public mutating func reveal() {
    showingAnswer = true
  }

  @discardableResult
  public mutating func nextCard() -> Bool {
    guard index + 1 < cards.count else { return false }
    index += 1
    showingAnswer = false
    return true
  }

  public mutating func back() {
    if showingAnswer {
      showingAnswer = false
    } else if index > 0 {
      index -= 1
      showingAnswer = true
    }
  }
}

import AppIntents
import Jotai
import SwiftData
import SwiftUI
import models

struct MyAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: ShowCardIntent(),
      phrases: ["Show card in \(.applicationName)"],
      shortTitle: "Show card",
      systemImageName: "creditcard.fill"
    )
  }
}

struct ShowCardIntent: AppIntent {
  static var title: LocalizedStringResource = "Show card"
  static var openAppWhenRun: Bool = true

  @Parameter(title: "Card")
  var card: CardEntity

  func perform() async throws -> some IntentResult {
    JotaiStore.shared.set(atom: startCardAtom, value: card.id)
    return .result()
  }
}

struct CardEntity: AppEntity, Identifiable {
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Card"

  var id: UUID
  var title: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title)")
  }

  static var defaultQuery = CardEntityQuery()
}
struct CardEntityQuery: EntityQuery {
  func entities(for identifiers: [UUID]) async throws -> [CardEntity] {
    let context = try ModelContext(.init(for: CardModel.self))
    let cards = try context.fetch(FetchDescriptor<CardModel>())
    return
      cards
      .filter { identifiers.contains($0.id) }
      .map { CardEntity(id: $0.id, title: $0.title) }
  }

  func suggestedEntities() async throws -> [CardEntity] {
    let context = try ModelContext(.init(for: CardModel.self))
    let cards = try context.fetch(FetchDescriptor<CardModel>(sortBy: [.init(\.title)]))
    return
      cards
      // .prefix(10)
      .map { CardEntity(id: $0.id, title: $0.title) }
  }
}

public let startCardAtom = PrimitiveAtom<UUID?>(nil)

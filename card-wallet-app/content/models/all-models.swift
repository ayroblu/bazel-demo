import Foundation
import Log
import SwiftData

let container = LazyValue { try! ModelContainer(for: CardModel.self, LogEntry.self) }

@MainActor
func getModelContext() throws -> ModelContext {
  return container.value.mainContext
}

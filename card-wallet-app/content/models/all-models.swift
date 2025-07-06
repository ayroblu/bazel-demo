import Foundation
import Log
import SwiftData

let modelContainer = LazyValue { try! ModelContainer(for: CardModel.self, LogEntry.self) }

@MainActor
func getModelContext() throws -> ModelContext {
  return modelContainer.value.mainContext
}

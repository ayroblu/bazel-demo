import Foundation
import Log
import SwiftData

public let modelContainer = LazyValue { try! ModelContainer(for: CardModel.self, LogEntry.self) }

@MainActor
public func getModelContext() throws -> ModelContext {
  return modelContainer.value.mainContext
}

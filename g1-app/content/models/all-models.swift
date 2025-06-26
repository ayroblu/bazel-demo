import Foundation
import Log
import SwiftData

var cachedContainer: ModelContainer?

public func getModelContainer() -> ModelContainer? {
  do {
    return try getModelContainerThrows()
  } catch {
    log("getModelContainer", error)
    return nil
  }
}
func getModelContainerThrows() throws -> ModelContainer {
  if let cachedContainer {
    return cachedContainer
  }
  let container = try ModelContainer(
    for:
      GlassesModel.self,
    NoteModel.self,
    LogEntry.self,
    NotifAppsModel.self,
    SearchHistoryModel.self,
  )
  cachedContainer = container
  return container
}
@MainActor
func getModelContext() throws -> ModelContext {
  return try getModelContainerThrows().mainContext
}


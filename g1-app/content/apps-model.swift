import Foundation
import Log
import SwiftData

@Model
public class NotifAppsModel {
  @Attribute(.unique) public var id: String
  var name: String
  var enabled: Bool = true

  init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

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
    NotifAppsModel.self
  )
  cachedContainer = container
  return container
}
@MainActor
func getModelContext() throws -> ModelContext {
  return try getModelContainerThrows().mainContext
}

@MainActor
func fetchNotifApps() throws -> [NotifAppsModel] {
  let context = try getModelContext()
  let predicate = #Predicate<NotifAppsModel> { $0.enabled == true }
  let descriptor = FetchDescriptor<NotifAppsModel>(
    predicate: predicate, sortBy: [SortDescriptor(\.name)])
  return try context.fetch(descriptor)
}

@MainActor
func insertOrUpdateNotifApp(id: String, name: String) throws {
  let context = try getModelContext()
  let predicate = #Predicate<NotifAppsModel> { $0.id == id }
  let descriptor = FetchDescriptor<NotifAppsModel>(predicate: predicate)
  let existingApps = try context.fetch(descriptor)

  if let existingApp = existingApps.first {
    existingApp.name = name
  } else {
    let newApp = NotifAppsModel(id: id, name: name)
    context.insert(newApp)
  }

  try context.save()
}

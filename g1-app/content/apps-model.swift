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

var cachedContext: ModelContext?

@MainActor
func getModelContext() throws -> ModelContext {
  if let cachedContext {
    return cachedContext
  }
  let container = try ModelContainer(for: NotifAppsModel.self)
  let context = container.mainContext
  cachedContext = context
  return context
}

@MainActor
func fetchNotifApps() throws -> [NotifAppsModel] {
  let context = try getModelContext()
  let descriptor = FetchDescriptor<NotifAppsModel>(sortBy: [SortDescriptor(\.name)])
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

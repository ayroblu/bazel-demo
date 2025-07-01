import Foundation
import SwiftData

@Model
class KvCacheModel {
  var key: String
  var value: String
  var ttl: Date?

  init(key: String, value: String, ttl: Date? = nil) {
    self.key = key
    self.value = value
    self.ttl = ttl
  }

  #Index<KvCacheModel>([\.key])
  #Unique<KvCacheModel>([\.key])
}

@MainActor
func getWithCache(key: String, onCacheMiss: () async throws -> (String, Date?)) async throws -> String {
  let context = try getModelContext()
  let predicate = #Predicate<KvCacheModel> { $0.key == key }
  let descriptor = FetchDescriptor<KvCacheModel>(predicate: predicate)
  let result = try context.fetch(descriptor)
  if let first = result.first {
    if let ttl = first.ttl {
      if ttl > Date.now {
        return first.value
      }
    } else {
      return first.value
    }
    context.delete(first)
  }
  let (newValue, ttl) = try await onCacheMiss()
  let model = KvCacheModel(key: key, value: newValue, ttl: ttl)
  context.insert(model)
  try context.save()
  return newValue
}

@MainActor
func insertOrUpdateCache(key: String, value: String, ttl: Date? = nil) throws {
  let context = try getModelContext()
  let predicate = #Predicate<KvCacheModel> { $0.key == key }
  let descriptor = FetchDescriptor<KvCacheModel>(predicate: predicate)
  let existingModels = try context.fetch(descriptor)

  if let existingModel = existingModels.first {
    existingModel.value = value
    existingModel.ttl = ttl
  } else {
    let model = KvCacheModel(key: key, value: value)
    context.insert(model)
  }

  try context.save()
}

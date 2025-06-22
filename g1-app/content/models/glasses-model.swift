import SwiftData

@Model
public class GlassesModel {
  @Attribute(.unique) var left: String
  @Attribute(.unique) var right: String
  var deviceSerialNumber: String?
  var leftLensSerialNumber: String?
  var rightLensSerialNumber: String?

  init(left: String, right: String) {
    self.left = left
    self.right = right
  }
}

@MainActor
func fetchGlassesModel() throws -> GlassesModel? {
  let context = try getModelContext()
  let descriptor = FetchDescriptor<GlassesModel>()
  let existingModels = try context.fetch(descriptor)
  if existingModels.count > 1 {
    for model in existingModels.dropFirst() {
      context.delete(model)
    }
  }
  return existingModels.first
}

@MainActor
func insertOrUpdateGlassesModel(left: String, right: String) throws -> GlassesModel {
  let context = try getModelContext()
  if let existingModel = try fetchGlassesModel() {
    existingModel.left = left
    existingModel.right = right
    try context.save()
    return existingModel
  } else {
    let newModel = GlassesModel(left: left, right: right)
    context.insert(newModel)
    try context.save()
    return newModel
  }
}

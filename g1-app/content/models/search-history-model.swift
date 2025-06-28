import Foundation
import SwiftData

@Model
class SearchHistoryModel: Identifiable {
  var id: String
  var title: String
  var thoroughfare: String?
  var subThoroughfare: String?
  var lat: Double
  var lng: Double
  var lastUpdated: Date = Date()

  init(
    id: String, title: String, thoroughfare: String?, subThoroughfare: String?, lat: Double,
    lng: Double
  ) {
    self.id = id
    self.title = title
    self.thoroughfare = thoroughfare
    self.subThoroughfare = subThoroughfare
    self.lat = lat
    self.lng = lng
  }
}

@MainActor
func insertOrUpdateSearchHistory(
  id: String, title: String, thoroughfare: String?, subThoroughfare: String?, lat: Double,
  lng: Double
) throws {
  let context = try getModelContext()
  let predicate = #Predicate<SearchHistoryModel> {
    $0.id == id || ($0.lat == lat && $0.lng == lng && $0.title == title)
  }
  let descriptor = FetchDescriptor<SearchHistoryModel>(predicate: predicate)
  let existingModels = try context.fetch(descriptor)

  if let existingModel = existingModels.first {
    existingModel.title = title
    existingModel.thoroughfare = thoroughfare
    existingModel.subThoroughfare = subThoroughfare
    existingModel.lat = lat
    existingModel.lng = lng
  } else {
    let newModel = SearchHistoryModel(
      id: id, title: title, thoroughfare: thoroughfare, subThoroughfare: subThoroughfare, lat: lat,
      lng: lng)
    context.insert(newModel)
  }

  try context.save()
}

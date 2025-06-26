import Foundation
import SwiftData

@Model
class SearchHistoryModel {
  var id: String?
  var title: String
  var lastUpdated: Date = Date()

  init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}

import Foundation
import SwiftData

@Model
class Log {
  var timestamp: Date
  var key: String
  var text: String

  init(timestamp: Date, key: String, text: String) {
    self.timestamp = timestamp
    self.key = key
    self.text = text
  }
}

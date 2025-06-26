import Foundation
import SwiftData

@Model
class NoteModel {
  var title: String = ""
  var text: String = ""

  init() {}

  init(title: String, text: String) {
    self.title = title
    self.text = text
  }
}

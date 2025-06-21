import Foundation
import SwiftData

@Model
public class NoteModel {
  var title: String = ""
  var text: String = ""

  init() {}

  init(title: String, text: String) {
    self.title = title
    self.text = text
  }
}

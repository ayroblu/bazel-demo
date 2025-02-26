import SwiftData

@Model
public class GlassesModel {
  @Attribute(.unique) var left: String
  @Attribute(.unique) var right: String

  init(left: String, right: String) {
    self.left = left
    self.right = right
  }
}

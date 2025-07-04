import SwiftData

@Model
class CardModel {
  var title: String
  var barcode: String
  var colour: String?
  var logo: String?

  init(title: String, barcode: String, colour: String? = nil, logo: String? = nil) {
    self.title = title
    self.barcode = barcode
    self.colour = colour
    self.logo = logo
  }
}

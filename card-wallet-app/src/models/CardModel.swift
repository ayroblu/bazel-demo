import Foundation
import SwiftData

@Model
public class CardModel {
  @Attribute(.unique) public var id: UUID = UUID()
  public var title: String
  public var barcode: String
  public var colour: String?
  public var logo: String?
  public var isQr: Bool = false
  public var notes: String = ""

  #Index<CardModel>([\.id])

  public init(title: String, barcode: String, colour: String? = nil, logo: String? = nil) {
    self.id = UUID()
    self.title = title
    self.barcode = barcode
    self.colour = colour
    self.logo = logo
  }
}

/*
Note that adding a UUID to an existing model will generate duplicate UUIDS
Also seen here: https://stackoverflow.com/questions/79261406/swiftdata-adding-a-uuid-to-an-existing-model-always-creates-the-same-id
.onAppear {
  for card in cards {
    if cards.count(where: { c in card.id == c.id }) > 1 {
      print("updating id")
      card.id = UUID()
    }
  }
}
*/

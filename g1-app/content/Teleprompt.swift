import SwiftUI

struct Teleprompt: View {
  var body: some View {
    VStack {
      List {
        Text("Item")
        Text("Item")
      }
      Button("Bottom") {
        print("Pressed bottom")
      }
    }
  }
}

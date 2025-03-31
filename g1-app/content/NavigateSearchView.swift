import SwiftUI

struct NavigateSearchView: View {
  @StateObject var vm: MainVM
  @State var text: String = ""

  var body: some View {
    VStack {
      Button("test2") {
        vm.connectionManager.sendTestNavigate2()
      }
      .buttonStyle(.bordered)
      HStack {
        TextField("Location where you want to go...", text: $text)
        Button("go") {
          vm.connectionManager.sendTestNavigate3(text: text)
        }
        .buttonStyle(.bordered)
        .disabled(text.isEmpty)
      }
    }
  }
}

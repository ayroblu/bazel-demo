import Log
import SwiftUI

struct NavigateSearchView: View {
  @StateObject var vm: MainVM
  @State var text: String = ""
  @Environment(\.scenePhase) var scenePhase

  var body: some View {
    VStack {
      Button("test2") {
        vm.connectionManager.sendTestNavigate2()
      }
      .buttonStyle(.bordered)
      HStack {
        TextField("Location where you want to go...", text: $text)
        Button("go") {
          Task {
            vm.searchResults = await getSearchResults(textQuery: text)
          }
          // vm.connectionManager.sendTestNavigate3(text: text)
        }
        .buttonStyle(.bordered)
        .disabled(text.isEmpty)
      }
      List {
        ForEach(vm.searchResults) { result in
          VStack(alignment: .leading) {
            Text(result.title)
            Text(result.subtitle)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .onTapGesture {
            Task {
              guard let location = try? await getUserLocation() else {
                log("NavigateSearchView: no location found")
                return
              }
              let lat = location.coordinate.latitude
              let lng = location.coordinate.longitude
              vm.connectionManager.sendTestNavigate3(loc: (lat, lng), route: result.route)
            }
          }
        }
      }
      .scrollDismissesKeyboard(.immediately)
    }
    .onChange(of: scenePhase) { oldPhase, newPhase in
      if newPhase == .active {
        // Task {
        //   await requestLocation()
        // }
      }
    }
    .onAppear {
      Task {
        let _ = try? await LocationManager.shared.requestLocation()
      }
    }
  }
}

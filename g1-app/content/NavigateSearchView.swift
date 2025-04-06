import Log
import MapKit
import SwiftUI

struct NavigateSearchView: View {
  @StateObject var vm: MainVM
  @State var text: String = "Sainsburys"
  @Environment(\.scenePhase) var scenePhase

  var body: some View {
    VStack {
      HStack {
        TextField("Location where you want to go...", text: $text)
        Button("go") {
          Task {
            vm.searchResults = await getSearchResults(textQuery: text)
          }
        }
        .buttonStyle(.bordered)
        .disabled(text.isEmpty)
      }
      List {
        ForEach(vm.searchResults) { result in
          NavigationLink {
            NavigationDetails(vm: vm, route: result.route)
              .navigationTitle(result.title)
              .onAppear {
                vm.connectionManager.sendNavigate(route: result.route)
                vm.locationSubInner = LocationManager.shared.subLocation()
              }
              .onDisappear {
                vm.connectionManager.stopNavigate()
                vm.locationSubInner?()
              }
          } label: {
            VStack(alignment: .leading) {
              Text(result.title)
              Text(result.subtitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
        }
      }
      .scrollDismissesKeyboard(.immediately)
    }
    .onChange(of: scenePhase) { oldPhase, newPhase in
      if newPhase == .active {
        if vm.locationSub == nil {
          vm.locationSub = LocationManager.shared.subLocation()
        }
      } else if newPhase == .background {
        vm.locationSub?()
        vm.locationSub = nil
      }
    }
    .onAppear {
      if vm.locationSub == nil {
        vm.locationSub = LocationManager.shared.subLocation()
      }
    }
    .onDisappear {
      vm.locationSub?()
      vm.locationSub = nil
    }
  }
}

struct NavigationDetails: View {
  @StateObject var vm: MainVM
  let route: MKRoute

  var body: some View {
    List {
      ForEach(route.steps, id: \.self) { (step: MKRoute.Step) in
        VStack(alignment: .leading) {
          HStack {
            TransportTypeIcon(transportType: step.transportType)
            Text("\(Int(step.distance))m")
          }
          Text(step.instructions)
        }
      }
    }

  }
}

struct TransportTypeIcon: View {
  let transportType: MKDirectionsTransportType

  var body: some View {
    Image(systemName: iconName)
      .resizable()
      .scaledToFit()
      .frame(width: 24, height: 24)
  }

  private var iconName: String {
    switch transportType {
    case .automobile:
      return "car.fill"
    case .walking:
      return "figure.walk"
    case .transit:
      return "bus.fill"
    // case .bicycle:
    //   return "bicycle"
    case .any:
      return "map.fill"
    default:
      return "questionmark.circle"
    }
  }
}

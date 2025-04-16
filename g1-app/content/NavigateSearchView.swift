import Log
import MapKit
import SwiftUI

let navigationOptions: [MKDirectionsTransportType] = [.automobile, .transit, .walking]
struct NavigateSearchView: View {
  @StateObject var vm: MainVM
  @State var text: String = "Sainsburys"
  @State private var selectedOption: TransportOption = .walking
  @Environment(\.scenePhase) var scenePhase

  var body: some View {
    VStack {
      Picker("Transport Type", selection: $selectedOption) {
        ForEach(TransportOption.allCases) { option in
          Text(option.rawValue)
            .tag(option)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)
      SearchTextField(placeholder: "Where you want to go...", searchText: $text) {
        Task {
          vm.searchResults = await getSearchResults(
            textQuery: text, transportType: selectedOption.transportType)
        }
      }
      .padding(.horizontal)

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
      .contentMargins(.top, 0)
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

/// https://stackoverflow.com/a/58473985
struct SearchTextField: View {
  let placeholder: String
  @Binding var searchText: String
  let onSubmit: () -> Void

  var body: some View {
    HStack {
      Image(systemName: "magnifyingglass")

      TextField(placeholder, text: $searchText)
        .foregroundColor(.primary)

      Button(action: {
        searchText = ""
      }) {
        Image(systemName: "xmark.circle.fill").opacity(searchText == "" ? 0 : 1)
      }
    }
    .padding(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6))
    .foregroundColor(.secondary)
    .background(Color(.secondarySystemBackground))
    .cornerRadius(10.0)
    .submitLabel(.search)
    .onSubmit {
      onSubmit()
    }
  }
}

enum TransportOption: String, CaseIterable, Identifiable {
  case automobile = "Drive"
  case walking = "Walk"
  // Not supported for route requests
  // case transit = "Transit"

  var id: Self { self }

  var transportType: MKDirectionsTransportType {
    switch self {
    case .automobile: return .automobile
    case .walking: return .walking
    // case .transit: return .transit
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

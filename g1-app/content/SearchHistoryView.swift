import Log
import LogUtils
import MapKit
import SwiftData
import SwiftUI
import Jotai
import utils

let searchHistoryResultAtom = atomFamily({ (key: SearchHistoryModel) in
  asyncAtom(ttlS: 120.0) { _ in
    let location = getMKMapItem(lat: key.lat, lng: key.lng)
    log("getting result for", key.id, key.title)
    let route = await tryFn {
      try await getDirections(
        from: MKMapItem.forCurrentLocation(), to: location,
        // TODO: get transportType from atom / state
        transportType: .walking
      )
    }
    log("got route for", key.id, key.title)
    guard let route else { return nil as LocSearchResult? }
    return LocSearchResult.from(item: key, route: route)
  }
})
struct SearchHistoryView: View {
  @StateObject var vm: MainVM
  @Query(sort: \SearchHistoryModel.lastUpdated, order: .reverse) var history: [SearchHistoryModel]

  var body: some View {
    List {
      Section(header: Text("Recent history")) {
        ForEach(history) { item in
          // 3km on the diagonal is a bit less than 5km
          if let distance = item.distanceFromCurrentLocationM(), distance < 5000 {
            SearchHistoryItemView(vm: vm, history: item)
          }
        }
        .onDelete(perform: deleteItems)
      }
    }
    // .scrollDismissesKeyboard(.immediately)
    // .contentMargins(.top, 0)
  }

  func deleteItems(at offsets: IndexSet) {
    for offset in offsets {
      try? getModelContext().delete(history[offset])
    }
  }
}
struct SearchHistoryItemView: View {
  @StateObject var vm: MainVM
  @AtomValue var loc: AsyncState<LocSearchResult?>

  init(vm: MainVM, history: SearchHistoryModel) {
    _vm = StateObject(wrappedValue: vm)
    _loc = AtomValue(searchHistoryResultAtom(history))
  }

  var body: some View {
    switch loc {
    case .pending:
      EmptyView()
    case .resolved(let data):
      if let data {
        SearchResultView(vm: vm, result: data)
      } else {
        EmptyView()
      }
    }
  }
}

extension LocSearchResult {
  static func from(item: SearchHistoryModel, route: MKRoute) -> LocSearchResult {
    let id = item.id
    let title = item.title
    let thoroughfare = item.thoroughfare
    let subThoroughfare = item.subThoroughfare
    let distance = route.distance
    let expectedTravelTime = route.expectedTravelTime
    let subtitle = [
      prettyPrintDistance(distance), expectedTravelTime.prettyPrintMinutes(), subThoroughfare,
      thoroughfare,
    ]
    .compactMap { $0 }.joined(separator: " ")
    return LocSearchResult(id: id, route: route, title: title, subtitle: subtitle)
  }
}

extension SearchHistoryModel {
  func distanceFromCurrentLocationM() -> Double? {
    guard let currentLocation = getCurrentLocation() else { return nil }
    let loc = CLLocation(latitude: self.lat, longitude: self.lng)
    return loc.distance(from: currentLocation)
  }
}

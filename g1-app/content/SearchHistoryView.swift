import LogUtils
import MapKit
import SwiftData
import SwiftUI
import jotai
import utils

let family = atomFamily({ (key: SearchHistoryModel) in
  asyncAtom({ _ in
    let location = MKMapItem.forCurrentLocation()
    let route = await tryFn {
      // try await getDirections(
      //   from: here, to: location,
      //   transportType: transportType)
      try await getDirections(
        from: MKMapItem.forCurrentLocation(), to: location,
        transportType: .walking
      )
    }
    guard let route else { return nil as LocSearchResult? }
    return LocSearchResult.from(item: location, route: route)
  })
})
struct SearchHistoryView: View {
  @StateObject var vm: MainVM
  @Query(sort: \SearchHistoryModel.lastUpdated, order: .reverse) var history: [SearchHistoryModel]

  var body: some View {
    List {
      ForEach(history) { item in
        SearchHistoryItemView(vm: vm, history: item)
      }
    }
  }
}
struct SearchHistoryItemView: View {
  @StateObject var vm: MainVM
  @AtomValue var loc: AsyncState<LocSearchResult?>

  init(vm: MainVM, history: SearchHistoryModel) {
    _vm = StateObject(wrappedValue: vm)
    _loc = AtomValue(family(history))
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

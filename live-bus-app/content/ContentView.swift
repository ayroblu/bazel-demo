import MapKit
import SwiftUI
import location
import tfl

public struct ContentView: View {
  @State private var model = BusMapModel()
  @State private var location = LocationModel.shared
  @State private var sheet: MapSheet?
  @State private var mapController = MapController()
  @State private var arrivalTarget: ArrivalTarget?

  public init() {}

  public var body: some View {
    GeometryReader { geometry in
      TimelineView(
        .animation(
          minimumInterval: 1, paused: model.tracks.isEmpty && model.stopTracks.isEmpty)
      ) { context in
        BusMapView(
          route: model.route,
          showsRouteStops: model.isZoomedIn,
          stopLetters: model.route == nil && model.showsStopLetters ? model.nearbyStops : [],
          focusedStop: focusedStop,
          dotStops: model.route == nil ? model.allStops : [],
          dotStopsVersion: model.allStopsVersion,
          buses: (model.route == nil ? model.stopTracks : model.tracks).compactMap {
            $0.position(at: context.date)
          },
          busesShowLineNames: model.route == nil,
          insets: geometry.safeAreaInsets,
          controller: mapController,
          onCameraChange: { model.cameraChanged(region: $0) },
          onSelectStop: { focus($0) },
          onSelectBus: { selectBus($0) })
      }
      .ignoresSafeArea()
    }
    .overlay(alignment: .bottomTrailing) {
      LocationButton(isEnabled: location.location != nil) {
        centerOnUser()
      }
    }
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 8) {
        if model.errorMessage != nil || location.isDenied {
          StatusBanner(errorMessage: model.errorMessage, isLocationDenied: location.isDenied)
        }
        RouteHeader(model: model, sheet: $sheet)
      }
      .padding(.bottom, 8)
    }
    .sheet(item: $sheet) { item in
      sheetContent(item)
    }
    .task {
      await model.loadLines()
    }
    .task {
      await model.loadAllStops()
    }
    .task {
      await location.run()
    }
    .onChange(of: location.location == nil) {
      guard model.route == nil else { return }
      centerOnUser()
    }
    .onChange(of: model.route?.lineId) {
      guard let route = model.route, arrivalTarget == nil else { return }
      mapController.show(route.mapRect, margin: routeFrameMargin)
    }
    .onChange(of: model.lastUpdate) {
      frameArrivalTarget()
    }
    .onChange(of: model.selectedLineId == nil) {
      guard model.selectedLineId == nil else { return }
      centerOnUser()
    }
    .onChange(of: sheet?.id) {
      if case .stop = sheet { return }
      model.unfocusStop()
    }
    .onOpenURL { url in
      openURL(url)
    }
  }

  @ViewBuilder private func sheetContent(_ item: MapSheet) -> some View {
    switch item {
    case .routes:
      RoutePickerView(lines: model.lines, nearbyLines: model.nearbyLines(from: location.location)) {
        lineId in
        selectLine(lineId)
      }
    case .stop(let stop):
      StopArrivalsView(
        stop: stop,
        onSelectArrival: {
          selectLine($0.lineId, target: ArrivalTarget(vehicleId: $0.vehicleId, stop: stop))
        },
        onSelectLine: { selectLine($0) }
      )
      .presentationDetents([.medium, .large])
      .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    case .bus(let id):
      BusDetailView(track: model.tracks.first { $0.id == id })
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
  }

  private func centerOnUser() {
    guard let userLocation = location.location else { return }
    mapController.show(
      MKCoordinateRegion(
        center: userLocation.coordinate, latitudinalMeters: 800, longitudinalMeters: 800))
  }

  private var focusedStop: BusStop? {
    if case .stop(let stop) = sheet {
      stop
    } else if model.selectedLineId != nil {
      arrivalTarget?.stop
    } else {
      nil
    }
  }

  private func focus(_ stop: BusStop) {
    sheet = .stop(stop)
    mapController.focus(on: stop.coordinate.clCoordinate, zoomIn: !model.showsStopLetters)
    model.focusStop(stop)
  }

  private func selectBus(_ vehicleId: String) {
    guard model.route == nil else {
      sheet = .bus(vehicleId)
      return
    }
    guard let stop = focusedStop, let track = model.stopTracks.first(where: { $0.id == vehicleId })
    else { return }
    selectLine(track.lineId, target: ArrivalTarget(vehicleId: vehicleId, stop: stop))
  }

  private func selectLine(_ lineId: String, target: ArrivalTarget? = nil) {
    arrivalTarget = target
    sheet = nil
    model.showRoute(lineId: lineId)
  }

  private func frameArrivalTarget() {
    guard let target = arrivalTarget, !target.isFramed, let route = model.route,
      model.lastUpdate != nil
    else { return }
    arrivalTarget?.isFramed = true
    guard let bus = model.tracks.first(where: { $0.id == target.vehicleId }),
      let position = bus.position(at: Date())
    else {
      mapController.show(route.mapRect, margin: routeFrameMargin)
      return
    }
    let points = [position.coordinate, target.stop.coordinate].map { MKMapPoint($0.clCoordinate) }
    let rect = points.reduce(MKMapRect.null) {
      $0.union(MKMapRect(origin: $1, size: MKMapSize()))
    }
    let minSize =
      MKMapPointsPerMeterAtLatitude(target.stop.coordinate.lat) * minArrivalFrameMeters
    mapController.show(
      rect.insetBy(
        dx: -max(0, minSize - rect.width) / 2, dy: -max(0, minSize - rect.height) / 2),
      margin: arrivalFrameMargin)
  }

  private func openURL(_ url: URL) {
    guard url.scheme == "livebus", let id = url.pathComponents.dropFirst().first else { return }
    switch url.host() {
    case "route":
      selectLine(id.lowercased())
    case "stop":
      Task {
        guard let stop = await model.openStop(id: id) else { return }
        focus(stop)
      }
    default:
      break
    }
  }
}

struct ArrivalTarget {
  let vehicleId: String
  let stop: BusStop
  var isFramed = false
}

enum MapSheet: Identifiable {
  case routes
  case stop(BusStop)
  case bus(String)

  var id: String {
    switch self {
    case .routes: "routes"
    case .stop(let stop): "stop-\(stop.id)"
    case .bus(let id): "bus-\(id)"
    }
  }
}

struct RouteHeader: View {
  let model: BusMapModel
  @Binding var sheet: MapSheet?

  var body: some View {
    HStack(spacing: 12) {
      if let lineId = model.selectedLineId {
        RouteBadge(name: model.route?.lineName ?? lineId.uppercased())
        VStack(alignment: .leading, spacing: 2) {
          if let ends = model.route?.ends {
            Text(ends)
              .font(.subheadline)
              .lineLimit(1)
          }
          Text(
            "\(updateText) · \(Text("●").foregroundStyle(directionColor("outbound"))) out \(Text("●").foregroundStyle(directionColor("inbound"))) in"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Button {
          model.clearRoute()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.title2)
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Clear route")
      } else {
        VStack(alignment: .leading, spacing: 2) {
          Text("Live London buses")
            .font(.headline)
          Text("Tap a stop or choose a route")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      Button {
        sheet = .routes
      } label: {
        Image(systemName: "magnifyingglass")
          .font(.title3)
      }
      .accessibilityLabel("Choose route")
    }
    .padding(12)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .padding(.horizontal)
  }

  private var updateText: String {
    guard model.route != nil, let lastUpdate = model.lastUpdate else { return "Loading…" }
    let buses = model.tracks.count == 1 ? "1 bus" : "\(model.tracks.count) buses"
    return "\(buses) · \(lastUpdate.formatted(date: .omitted, time: .standard))"
  }
}

struct LocationButton: View {
  let isEnabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "location.fill")
        .font(.title3)
        .frame(width: 44, height: 44)
    }
    .background(.regularMaterial, in: Circle())
    .disabled(!isEnabled)
    .accessibilityLabel("Show my location")
    .padding(.bottom, 8)
    .padding(.trailing, 16)
  }
}

struct StatusBanner: View {
  let errorMessage: String?
  let isLocationDenied: Bool

  var body: some View {
    VStack(spacing: 8) {
      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
      }
      if isLocationDenied {
        Label(
          "Location access is off, so the map can't show where you are",
          systemImage: "location.slash")
      }
    }
    .font(.footnote)
    .padding(12)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .padding(.horizontal)
  }
}

extension BusRoute {
  var mapRect: MKMapRect {
    paths.flatMap(\.coordinates).reduce(MKMapRect.null) { rect, coordinate in
      rect.union(MKMapRect(origin: MKMapPoint(coordinate.clCoordinate), size: MKMapSize()))
    }
  }

  var ends: String? {
    guard let path = paths.first, let first = path.stops.first, let last = path.stops.last
    else { return nil }
    return "\(first.stop.name) ↔ \(last.stop.name)"
  }
}

private let routeFrameMargin: CGFloat = 12
private let arrivalFrameMargin: CGFloat = 60
private let minArrivalFrameMeters = 400.0

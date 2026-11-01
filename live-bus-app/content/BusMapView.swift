import MapKit
import SwiftUI
import tfl

struct BusMapView: UIViewRepresentable {
  let route: BusRoute?
  let showsRouteStops: Bool
  let stopLetters: [BusStop]
  let focusedStop: BusStop?
  let dotStops: [BusStop]
  let dotStopsVersion: Int
  let buses: [BusPosition]
  let busesShowLineNames: Bool
  let insets: EdgeInsets
  let controller: MapController
  let onCameraChange: (MKCoordinateRegion) -> Void
  let onSelectStop: (BusStop) -> Void
  let onSelectBus: (String) -> Void

  func makeUIView(context: Context) -> MKMapView {
    let mapView = MKMapView()
    mapView.delegate = context.coordinator
    mapView.showsUserLocation = true
    mapView.isRotateEnabled = false
    mapView.isPitchEnabled = false
    mapView.showsCompass = false
    mapView.showsScale = true
    mapView.pointOfInterestFilter = .excludingAll
    mapView.insetsLayoutMarginsFromSafeArea = false
    mapView.setRegion(londonRegion, animated: false)
    let tap = UITapGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
    tap.delegate = context.coordinator
    for doubleTap in doubleTapRecognizers(in: mapView) {
      tap.require(toFail: doubleTap)
    }
    mapView.addGestureRecognizer(tap)
    controller.mapView = mapView
    return mapView
  }

  func updateUIView(_ mapView: MKMapView, context: Context) {
    context.coordinator.parent = self
    let margins = UIEdgeInsets(
      top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing)
    if mapView.layoutMargins != margins {
      mapView.layoutMargins = margins
    }
    controller.insets = margins
    context.coordinator.update(mapView)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
    var parent: BusMapView
    private var routeLineId: String?
    private var routeLines: [MKPolyline] = []
    private var routeStopsOverlay: StopDotsOverlay?
    private var dotsOverlay: StopDotsOverlay?
    private var dotsVersion: Int?
    private var stopAnnotations: [String: StopAnnotation] = [:]
    private var focusedStopId: String?
    private var busAnnotations: [String: BusAnnotation] = [:]

    init(parent: BusMapView) {
      self.parent = parent
    }

    func update(_ mapView: MKMapView) {
      updateRoute(mapView)
      updateDots(mapView)
      updateStopLetters(mapView)
      updateBuses(mapView)
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
      if let dots = overlay as? StopDotsOverlay {
        return StopDotsRenderer(dots: dots)
      }
      let renderer = MKPolylineRenderer(overlay: overlay)
      renderer.strokeColor = UIColor(directionColor((overlay as? MKPolyline)?.title ?? ""))
        .withAlphaComponent(0.6)
      renderer.lineWidth = 4
      return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
      switch annotation {
      case let stop as StopAnnotation:
        let view =
          mapView.dequeueReusableAnnotationView(withIdentifier: StopAnnotationView.reuseId)
          as? StopAnnotationView
          ?? StopAnnotationView(annotation: stop, reuseIdentifier: StopAnnotationView.reuseId)
        view.annotation = stop
        return view
      case let bus as BusAnnotation:
        let view =
          mapView.dequeueReusableAnnotationView(withIdentifier: BusAnnotationView.reuseId)
          as? BusAnnotationView
          ?? BusAnnotationView(annotation: bus, reuseIdentifier: BusAnnotationView.reuseId)
        view.annotation = bus
        return view
      default:
        return nil
      }
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
      mapView.deselectAnnotation(annotation, animated: false)
      switch annotation {
      case let stop as StopAnnotation:
        parent.onSelectStop(stop.stop)
      case let bus as BusAnnotation:
        parent.onSelectBus(bus.id)
      default:
        break
      }
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
      parent.onCameraChange(mapView.region)
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
      guard let mapView = gesture.view as? MKMapView, mapView.bounds.width > 0 else { return }
      let stops =
        if let route = parent.route {
          parent.showsRouteStops ? route.stops : []
        } else {
          parent.dotStops
        }
      let tapPoint = MKMapPoint(
        mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView))
      let maxDistance = maxTapDistance * mapView.visibleMapRect.width / mapView.bounds.width
      let nearest = stops.map { stop in
        (stop: stop, distance: MKMapPoint(stop.coordinate.clCoordinate).distance(to: tapPoint))
      }
      .filter { $0.distance < maxDistance }
      .min { $0.distance < $1.distance }
      if let stop = nearest?.stop {
        parent.onSelectStop(stop)
      }
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
    ) -> Bool {
      var view = touch.view
      while let current = view {
        if current is MKAnnotationView { return false }
        view = current.superview
      }
      return true
    }

    private func updateRoute(_ mapView: MKMapView) {
      if parent.route?.lineId != routeLineId {
        mapView.removeOverlays(routeLines)
        routeStopsOverlay.map(mapView.removeOverlay)
        routeStopsOverlay = nil
        routeLineId = parent.route?.lineId
        routeLines =
          parent.route?.paths.map { path in
            let line = MKPolyline(
              coordinates: path.coordinates.map(\.clCoordinate), count: path.coordinates.count)
            line.title = path.direction
            return line
          } ?? []
        mapView.addOverlays(routeLines, level: .aboveRoads)
      }
      let wantsRouteStops = parent.route != nil && parent.showsRouteStops
      if wantsRouteStops, routeStopsOverlay == nil, let route = parent.route {
        let overlay = StopDotsOverlay(stops: route.stops, style: .routeStop)
        mapView.addOverlay(overlay, level: .aboveLabels)
        routeStopsOverlay = overlay
      } else if !wantsRouteStops, let overlay = routeStopsOverlay {
        mapView.removeOverlay(overlay)
        routeStopsOverlay = nil
      }
    }

    private func updateDots(_ mapView: MKMapView) {
      let version = parent.dotStops.isEmpty ? nil : parent.dotStopsVersion
      guard version != dotsVersion else { return }
      dotsOverlay.map(mapView.removeOverlay)
      dotsOverlay = nil
      dotsVersion = version
      guard version != nil else { return }
      let overlay = StopDotsOverlay(stops: parent.dotStops, style: .stop)
      mapView.addOverlay(overlay, level: .aboveLabels)
      dotsOverlay = overlay
    }

    private func updateStopLetters(_ mapView: MKMapView) {
      let focusedId = parent.focusedStop?.id
      let stops = parent.stopLetters + (parent.focusedStop.map { [$0] } ?? [])
      let wanted = Dictionary(stops.map { ($0.id, $0) }) { first, _ in first }
      let removed = stopAnnotations.filter { wanted[$0.key] == nil }
      mapView.removeAnnotations(Array(removed.values))
      for id in removed.keys {
        stopAnnotations[id] = nil
      }
      let added = wanted.filter { stopAnnotations[$0.key] == nil }.mapValues {
        StopAnnotation($0, isFocused: $0.id == focusedId)
      }
      mapView.addAnnotations(Array(added.values))
      stopAnnotations.merge(added) { _, new in new }
      guard focusedId != focusedStopId else { return }
      for id in [focusedStopId, focusedId].compactMap({ $0 }) {
        guard let annotation = stopAnnotations[id] else { continue }
        annotation.isFocused = id == focusedId
        (mapView.view(for: annotation) as? StopAnnotationView)?.configure()
      }
      focusedStopId = focusedId
    }

    private func updateBuses(_ mapView: MKMapView) {
      let wanted = Dictionary(parent.buses.map { ($0.id, $0) }) { first, _ in first }
      let removed = busAnnotations.filter { wanted[$0.key] == nil }
      mapView.removeAnnotations(Array(removed.values))
      for id in removed.keys {
        busAnnotations[id] = nil
      }
      for (id, bus) in wanted {
        if let annotation = busAnnotations[id] {
          annotation.coordinate = bus.coordinate.clCoordinate
          annotation.heading = bus.heading
          annotation.direction = bus.direction
          annotation.showsLineName = parent.busesShowLineNames
          (mapView.view(for: annotation) as? BusAnnotationView)?.configure()
        } else {
          let annotation = BusAnnotation(bus, showsLineName: parent.busesShowLineNames)
          busAnnotations[id] = annotation
          mapView.addAnnotation(annotation)
        }
      }
    }
  }
}

final class MapController {
  weak var mapView: MKMapView?
  var insets = UIEdgeInsets.zero

  func show(_ region: MKCoordinateRegion) {
    let topLeft = MKMapPoint(
      CLLocationCoordinate2D(
        latitude: region.center.latitude + region.span.latitudeDelta / 2,
        longitude: region.center.longitude - region.span.longitudeDelta / 2))
    let bottomRight = MKMapPoint(
      CLLocationCoordinate2D(
        latitude: region.center.latitude - region.span.latitudeDelta / 2,
        longitude: region.center.longitude + region.span.longitudeDelta / 2))
    show(
      MKMapRect(
        x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x,
        height: bottomRight.y - topLeft.y))
  }

  func show(_ rect: MKMapRect, margin: CGFloat = 0) {
    mapView?.setVisibleMapRect(
      rect,
      edgePadding: UIEdgeInsets(
        top: insets.top + margin, left: insets.left + margin, bottom: insets.bottom + margin,
        right: insets.right + margin), animated: true)
  }

  func focus(on coordinate: CLLocationCoordinate2D, zoomIn: Bool) {
    guard let mapView, mapView.bounds.height > 0 else { return }
    let point = MKMapPoint(coordinate)
    let width =
      zoomIn
      ? MKMapPointsPerMeterAtLatitude(coordinate.latitude) * focusZoomMeters
      : mapView.visibleMapRect.width
    mapView.setVisibleMapRect(
      MKMapRect(x: point.x - width / 2, y: point.y - width / 20, width: width, height: width / 10),
      edgePadding: UIEdgeInsets(
        top: insets.top, left: 0, bottom: mapView.bounds.height * sheetHeightFraction, right: 0),
      animated: true)
  }
}

final class StopAnnotation: NSObject, MKAnnotation {
  let stop: BusStop
  let coordinate: CLLocationCoordinate2D
  var isFocused: Bool

  init(_ stop: BusStop, isFocused: Bool) {
    self.stop = stop
    self.isFocused = isFocused
    coordinate = stop.coordinate.clCoordinate
  }

  var title: String? { stop.name }
}

final class BusAnnotation: NSObject, MKAnnotation {
  let id: String
  let lineName: String
  @objc dynamic var coordinate: CLLocationCoordinate2D
  var heading: Double
  var direction: String
  var showsLineName: Bool

  init(_ bus: BusPosition, showsLineName: Bool) {
    id = bus.id
    lineName = bus.lineName
    coordinate = bus.coordinate.clCoordinate
    heading = bus.heading
    direction = bus.direction
    self.showsLineName = showsLineName
  }

  var title: String? { "Bus \(id)" }
}

final class StopAnnotationView: MKAnnotationView {
  static let reuseId = "stop"
  private let label = UILabel()
  private let icon = UIImageView(image: UIImage(systemName: "bus.fill"))

  override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
    super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
    layer.borderColor = UIColor.white.cgColor
    layer.shadowOffset = .zero
    label.textColor = .white
    label.textAlignment = .center
    icon.contentMode = .center
    icon.tintColor = .white
    addSubview(label)
    addSubview(icon)
    displayPriority = .required
    isAccessibilityElement = true
    configure()
  }

  required init?(coder: NSCoder) {
    nil
  }

  override var annotation: MKAnnotation? {
    didSet { configure() }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    label.frame = bounds
    icon.frame = bounds
    layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
  }

  func configure() {
    guard let annotation = annotation as? StopAnnotation else { return }
    let stop = annotation.stop
    let letter = stop.letter.flatMap { $0.count <= 2 && !$0.contains("->") ? $0 : nil }
    label.text = letter
    icon.isHidden = letter != nil
    accessibilityLabel = stop.name
    let size = annotation.isFocused ? focusedStopMarkerSize : stopMarkerSize
    label.font = .systemFont(ofSize: annotation.isFocused ? 16 : 11, weight: .bold)
    icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
      pointSize: annotation.isFocused ? 15 : 10)
    zPriority = annotation.isFocused ? .defaultSelected : .defaultUnselected
    UIView.animate(withDuration: 0.2) { [self] in
      bounds = CGRect(x: 0, y: 0, width: size, height: size)
      layer.cornerRadius = size / 2
      layer.borderWidth = annotation.isFocused ? 2.5 : 1.5
      layer.shadowOpacity = annotation.isFocused ? 0.45 : 0.3
      layer.shadowRadius = annotation.isFocused ? 3 : 1
      backgroundColor = UIColor(annotation.isFocused ? focusedStopRed : busRed)
    }
  }
}

final class BusAnnotationView: MKAnnotationView {
  static let reuseId = "bus"
  private let circle = UIView()
  private let arrow = UIImageView(
    image: UIImage(
      systemName: "arrow.up",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .black)))
  private let badge = UILabel()

  override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
    super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
    circle.layer.cornerRadius = busMarkerSize / 2
    circle.layer.borderColor = UIColor.black.cgColor
    circle.layer.borderWidth = 1.5
    arrow.frame = CGRect(x: 0, y: 0, width: busMarkerSize, height: busMarkerSize)
    arrow.contentMode = .center
    arrow.tintColor = .white
    circle.addSubview(arrow)
    badge.font = .systemFont(ofSize: 10, weight: .bold)
    badge.textColor = .white
    badge.textAlignment = .center
    badge.backgroundColor = UIColor.black.withAlphaComponent(0.75)
    badge.layer.cornerRadius = 4
    badge.clipsToBounds = true
    addSubview(circle)
    addSubview(badge)
    displayPriority = .required
    zPriority = .max
    isAccessibilityElement = true
    configure()
  }

  required init?(coder: NSCoder) {
    nil
  }

  override var annotation: MKAnnotation? {
    didSet { configure() }
  }

  func configure() {
    guard let bus = annotation as? BusAnnotation else { return }
    circle.backgroundColor = UIColor(bus.showsLineName ? busRed : directionColor(bus.direction))
    arrow.transform = CGAffineTransform(rotationAngle: bus.heading * .pi / 180)
    badge.isHidden = !bus.showsLineName
    badge.text = bus.lineName
    let badgeWidth = bus.showsLineName ? badge.intrinsicContentSize.width + 8 : 0
    let badgeHeight: CGFloat = bus.showsLineName ? busBadgeHeight : 0
    let width = max(busMarkerSize, badgeWidth)
    frame.size = CGSize(width: width, height: busMarkerSize + badgeHeight)
    badge.frame = CGRect(x: (width - badgeWidth) / 2, y: 0, width: badgeWidth, height: badgeHeight)
    circle.frame = CGRect(
      x: (width - busMarkerSize) / 2, y: badgeHeight, width: busMarkerSize, height: busMarkerSize)
    centerOffset = CGPoint(x: 0, y: -badgeHeight / 2)
    accessibilityLabel = bus.title
  }
}

struct DotStyle: Sendable {
  let fill: CGColor
  let stroke: CGColor
  let diameter: CGFloat
  let strokeWidth: CGFloat
  let cellSize: CGFloat

  static let stop = DotStyle(
    fill: UIColor(busRed).cgColor, stroke: UIColor.white.cgColor, diameter: 6, strokeWidth: 1,
    cellSize: 8)
  static let routeStop = DotStyle(
    fill: UIColor.systemYellow.cgColor, stroke: UIColor.black.cgColor, diameter: 10,
    strokeWidth: 2, cellSize: 10)
}

nonisolated final class StopDotsOverlay: NSObject, MKOverlay {
  let points: [MKMapPoint]
  let style: DotStyle
  let boundingMapRect: MKMapRect
  let coordinate: CLLocationCoordinate2D

  init(stops: [BusStop], style: DotStyle) {
    points = stops.map { MKMapPoint($0.coordinate.clCoordinate) }.sorted { $0.x < $1.x }
    self.style = style
    let bounds = points.reduce(MKMapRect.null) {
      $0.union(MKMapRect(origin: $1, size: MKMapSize()))
    }
    boundingMapRect = bounds.insetBy(dx: -bounds.width * 0.05 - 1, dy: -bounds.height * 0.05 - 1)
    coordinate = MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate
  }
}

nonisolated final class StopDotsRenderer: MKOverlayRenderer {
  private let points: [MKMapPoint]
  private let style: DotStyle
  private let origin: MKMapPoint

  init(dots: StopDotsOverlay) {
    points = dots.points
    style = dots.style
    origin = dots.boundingMapRect.origin
    super.init(overlay: dots)
  }

  override func draw(
    _ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext
  ) {
    let diameter = style.diameter / zoomScale
    let cell = style.cellSize / zoomScale
    let minCellX = ((mapRect.minX - diameter) / cell).rounded(.down) * cell
    let maxCellX = ((mapRect.maxX + diameter) / cell).rounded(.up) * cell
    let minCellY = ((mapRect.minY - diameter) / cell).rounded(.down) * cell
    let maxCellY = ((mapRect.maxY + diameter) / cell).rounded(.up) * cell
    var low = 0
    var high = points.count
    while low < high {
      let mid = (low + high) / 2
      if points[mid].x < minCellX { low = mid + 1 } else { high = mid }
    }
    var occupiedCells = Set<SIMD2<Int>>()
    let path = CGMutablePath()
    for point in points[low...] {
      guard point.x < maxCellX else { break }
      guard point.y >= minCellY, point.y < maxCellY,
        occupiedCells.insert(SIMD2(Int(point.x / cell), Int(point.y / cell))).inserted
      else { continue }
      path.addEllipse(
        in: CGRect(
          x: point.x - origin.x - diameter / 2, y: point.y - origin.y - diameter / 2,
          width: diameter, height: diameter))
    }
    context.addPath(path)
    context.setFillColor(style.fill)
    context.setStrokeColor(style.stroke)
    context.setLineWidth(style.strokeWidth / zoomScale)
    context.drawPath(using: .fillStroke)
  }
}

private let maxTapDistance: CGFloat = 22
private let stopMarkerSize: CGFloat = 24
private let focusedStopMarkerSize: CGFloat = 36
private let focusZoomMeters = 800.0
private let sheetHeightFraction = 0.5
private let focusedStopRed = Color(red: 0.62, green: 0.04, blue: 0.1)
private let busMarkerSize: CGFloat = 22
private let busBadgeHeight: CGFloat = 15

private let londonRegion = MKCoordinateRegion(
  center: CLLocationCoordinate2D(latitude: 51.507, longitude: -0.1277),
  latitudinalMeters: 2000, longitudinalMeters: 2000)

private func doubleTapRecognizers(in view: UIView) -> [UITapGestureRecognizer] {
  (view.gestureRecognizers ?? []).compactMap { $0 as? UITapGestureRecognizer }
    .filter { $0.numberOfTapsRequired == 2 }
    + view.subviews.flatMap(doubleTapRecognizers)
}

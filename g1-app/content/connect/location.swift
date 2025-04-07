import Collections
import CoreLocation
import Log
import utils

class LocationManager: NSObject, CLLocationManagerDelegate {
  static let shared = LocationManager()
  let locationManager = CLLocationManager()
  private var locationContinuation: CheckedContinuation<CLLocation, Error>?
  var location: CLLocation?
  var subLocation: () -> () -> Void = { {} }

  override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    // locationManager.desiredAccuracy = kCLLocationAccuracyBest
    if locationManager.authorizationStatus != .authorizedAlways {
      locationManager.requestAlwaysAuthorization()
    }
    subLocation = runWhileSubbed(
      start: { [self] in locationManager.startUpdatingLocation() },
      stop: { [self] in locationManager.stopUpdatingLocation() })
  }

  private func checkPermission() throws {
    guard CLLocationManager.locationServicesEnabled() else {
      throw LocationError.servicesDisabled
    }

    switch locationManager.authorizationStatus {
    case .notDetermined, .restricted, .denied:
      throw LocationError.permissionDenied
    case .authorizedAlways, .authorizedWhenInUse:
      break
    @unknown default:
      throw LocationError.unknown
    }
  }

  func requestLocation() async throws -> CLLocation {
    try checkPermission()
    return try await withCheckedThrowingContinuation { continuation in
      locationContinuation = continuation
      log("requestLocation")
      locationManager.requestLocation()
    }
  }

  var locationHistory = LocationHistory()

  func locationManager(
    _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
  ) {
    log("did update location")
    // if locationContinuation != nil { log("did update location") }
    guard let location = locations.last else { return }
    self.location = location
    locationContinuation?.resume(returning: location)
    locationContinuation = nil

    locationHistory.updateLocation(location: location)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    log("did fail location")
    locationContinuation?.resume(throwing: error)
    locationContinuation = nil
  }
}

enum LocationError: Error {
  case servicesDisabled
  case permissionDenied
  case unknown
}

func getUserLocation() async throws -> CLLocation {
  if let location = LocationManager.shared.location {
    return location
  } else if let location = LocationManager.shared.locationManager.location {
    return location
  } else {
    log("No location manager location")
    return try await LocationManager.shared.requestLocation()
  }
}

struct LocationHistory {
  private var history: Deque<CLLocation> = []

  mutating func updateLocation(location: CLLocation) {
    let now = Date()
    if let timestamp = history.last?.timestamp,
      now.timeIntervalSince(timestamp) < 1
    {
    } else {
      history.append(location)
    }
    while let firstLoc = history.first, now.timeIntervalSince(firstLoc.timestamp) > 20 {
      let _ = history.popFirst()
    }
  }

  /// m/s
  func getSpeed() -> Double {
    guard history.count > 1 else { return 0 }
    // either moving average of points, or first - last / time
    guard let first = history.first else { return 0 }
    guard let last = history.last else { return 0 }
    let timeInterval = last.timestamp.timeIntervalSince(first.timestamp)
    guard timeInterval > 0 else { return 0 }
    return first.distance(from: last) / timeInterval
  }

  func getAngle() -> Double {
    guard history.count > 1 else { return 0 }
    guard let first = history.first else { return 0 }
    guard let last = history.last else { return 0 }
    return calculateAngle(from: first, to: last)
  }
}

func calculateAngle(from startLocation: CLLocation, to endLocation: CLLocation) -> Double {
  let startLatitude = startLocation.coordinate.latitude * .pi / 180
  let startLongitude = startLocation.coordinate.longitude * .pi / 180
  let endLatitude = endLocation.coordinate.latitude * .pi / 180
  let endLongitude = endLocation.coordinate.longitude * .pi / 180

  let dLon = endLongitude - startLongitude

  let y = sin(dLon) * cos(endLatitude)
  let x = cos(startLatitude) * sin(endLatitude) - sin(startLatitude) * cos(endLatitude) * cos(dLon)

  let bearing = atan2(y, x)

  return bearing
}

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

  func locationManager(
    _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
  ) {
    log("did update location")
    // if locationContinuation != nil { log("did update location") }
    guard let location = locations.last else { return }
    self.location = location
    locationContinuation?.resume(returning: location)
    locationContinuation = nil
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

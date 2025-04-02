import CoreLocation
import Log

class LocationManager: NSObject, CLLocationManagerDelegate {
  static let shared = LocationManager()
  let locationManager = CLLocationManager()
  private var locationContinuation: CheckedContinuation<CLLocation, Error>?

  override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    // locationManager.desiredAccuracy = kCLLocationAccuracyBest
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
    guard let location = locations.last else { return }
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
  if let location = LocationManager.shared.locationManager.location {
    return location
  } else {
    return try await LocationManager.shared.requestLocation()
  }
}

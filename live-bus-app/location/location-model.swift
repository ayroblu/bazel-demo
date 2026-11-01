import CoreLocation
import Log
import Observation

@Observable public final class LocationModel {
  public static let shared = LocationModel()

  public private(set) var location: CLLocation?
  public private(set) var isDenied = false

  public func run() async {
    let session = CLServiceSession(authorization: .whenInUse)
    do {
      for try await update in CLLocationUpdate.liveUpdates() {
        isDenied = update.authorizationDenied || update.authorizationDeniedGlobally
        if let location = update.location {
          self.location = location
        }
      }
    } catch {
      log("location updates failed", error)
    }
    session.invalidate()
  }
}

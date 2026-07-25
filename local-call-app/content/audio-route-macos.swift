#if os(macOS)
import Foundation

// On macOS input/output devices follow the system default, so there is
// nothing to configure; this exists to mirror the iOS controller's API.
class AudioRouteController: ObservableObject {
  func activate() throws {}
  func deactivate() {}
}
#endif

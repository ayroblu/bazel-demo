#if canImport(WatchConnectivity)
  import WatchConnectivity
  import Log

  class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    private let session = WCSession.default

    private override init() {
      super.init()
      session.delegate = self
      session.activate()
      log("WatchConnectivity: activate")
    }

    // Handle received message from watch
    func session(
      _ session: WCSession, didReceiveMessage message: [String: Any],
      replyHandler: @escaping ([String: Any]) -> Void
    ) {
      log("WatchConnectivity: didReceiveMessage")
      if let integerValue = message["integerValue"] as? Int {
        log("WatchConnectivity: Received integer from watch: \(integerValue)")
        // Process the integer (e.g., update UI, save to storage)
        replyHandler(["status": "Received"])
      } else {
        replyHandler(["error": "Invalid integer"])
      }
    }

    // Required WCSessionDelegate methods
    func session(
      _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
      error: Error?
    ) {
      if let error = error {
        log("WatchConnectivity: Session activation failed: \(error)")
      } else {
        log("WatchConnectivity: Session activated with state: \(activationState.rawValue)")
      }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
      session.activate()  // Reactivate session if needed
    }
  }
#endif

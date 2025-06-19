import WatchConnectivity

class WatchConnectivityManager: NSObject, WCSessionDelegate {
  static let shared = WatchConnectivityManager()
  private let session = WCSession.default

  private override init() {
    super.init()
    session.delegate = self
    session.activate()
  }

  // Send an integer to the iOS app
  func sendInteger(_ value: Int) {
    guard session.isReachable else {
      print("iOS app is not reachable")
      return
    }
    let message = ["integerValue": value]
    print("sendInteger", value)
    session.sendMessage(
      message,
      replyHandler: { reply in
        print("Received reply from iOS: \(reply)")
      },
      errorHandler: { error in
        print("Error sending message: \(error)")
      })
  }

  // Required WCSessionDelegate methods
  func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if let error = error {
      print("Session activation failed: \(error)")
    } else {
      print("Session activated with state: \(activationState.rawValue)")
    }
  }

  // Handle reachability changes (optional)
  func sessionReachabilityDidChange(_ session: WCSession) {
    print("Reachability changed: \(session.isReachable)")
  }
}

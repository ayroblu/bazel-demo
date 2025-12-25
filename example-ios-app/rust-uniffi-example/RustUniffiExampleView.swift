import Log
import SwiftUI
import example
import http_shared_lib

public struct RustUniffiExampleView: View {
  @State var ip: String?
  public init() {
    registerUrlSessionHttpProvider()
  }
  public var body: some View {
    Text("add 1 + 2 = \(printAndAdd(a: 1, b: 2))")
      .onAppear {
        let cleanup = subber(
          thing: ClosureWrapper {
            log("I am a closure being called from Rust!")
          })
        cleanup.dispose()
        Task {
          ip = await checkNetwork()
        }
      }
    if let ip {
      Text("External ip: \(ip)")
    }
  }
}

final class ClosureWrapper: ClosureCallback {
  let callback: @Sendable () -> Void

  init(_ callback: @escaping @Sendable () -> Void) {
    self.callback = callback
  }

  func notif() {
    callback()
  }
}

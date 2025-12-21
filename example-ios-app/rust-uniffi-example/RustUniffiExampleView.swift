import Log
import SwiftUI
import example
import http_shared_lib

public struct RustUniffiExampleView: View {
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
          await checkNetwork()
        }
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

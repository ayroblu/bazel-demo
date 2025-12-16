import SwiftUI
import example

public struct RustUniffiExampleView: View {
  public init() {}
  public var body: some View {
    Text("add 1 + 2 = \(printAndAdd(a: 1, b: 2))")
      .onAppear {
        let cleanup = subber(
          thing: ClosureWrapper {
            print("I am a closure being called from Rust!")
          })
        cleanup.dispose()
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

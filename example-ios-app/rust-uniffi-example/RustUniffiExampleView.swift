import SwiftUI
import example

public struct RustUniffiExampleView: View {
  public init() {}
  public var body: some View {
    Text("add 1 + 2 = \(printAndAdd(a: 1, b: 2))")
  }
}

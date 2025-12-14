import SwiftUI
import uniffi

public struct SqliteExampleView: View {
  public init() {}
  public var body: some View {
    Text("values \(getSaved()?.joined(separator: "\n") ?? "nil")")
  }
}

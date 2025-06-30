import SwiftUI

/// https://stackoverflow.com/questions/57594159/swiftui-navigationlink-loads-destination-view-immediately-without-clicking
public struct NavigationLazyView<Content: View>: View {
  let build: () -> Content
  public init(_ build: @escaping () -> Content) {
    self.build = build
  }
  public var body: Content {
    build()
  }
}


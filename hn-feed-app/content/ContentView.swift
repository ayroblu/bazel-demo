import SwiftUI

public struct ContentView: View {
  public init() {}

  public var body: some View {
    TabView {
      Tab("YC200", systemImage: "chart.line.uptrend.xyaxis") {
        FeedView(title: "YC200", source: .newsyc200)
      }
      Tab("250+", systemImage: "flame") {
        FeedView(title: "250+", source: .newsyc250)
      }
      Tab("Front Page", systemImage: "newspaper") {
        FeedView(title: "Front Page", source: .frontPage)
      }
      Tab("Experimental", systemImage: "flask") {
        FeedView(title: "Experimental", source: .rising)
      }
    }
  }
}

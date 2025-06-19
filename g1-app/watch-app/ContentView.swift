import SwiftUI

struct ContentView: View {
  // var body: some View {
  //     VStack {
  //         Image(systemName: "globe")
  //             .imageScale(.large)
  //             .foregroundStyle(.tint)
  //         Text("Hello, world!")
  //     }
  //     .padding()
  // }

  // @State private var scrollOffset: CGFloat = 0

  //     var body: some View {
  //         ScrollView {
  //             GeometryReader { geometry in
  //                 VStack {
  //                     ForEach(0..<50) { index in
  //                         Text("Item \(index)")
  //                             .padding()
  //                     }
  //                 }
  //                 .onChange(of: geometry.frame(in: .global).minY) { oldValue, newValue in
  //                     scrollOffset = newValue
  //                     print("Scroll offset: \(scrollOffset)")
  //                 }
  //             }
  //         }
  //     }

  @State private var counter = 0

  var body: some View {
    VStack {
      Text("Counter: \(counter)")
        .font(.headline)
      Button("Send to iPhone") {
        counter += 1
        WatchConnectivityManager.shared.sendInteger(counter)
      }
      .buttonStyle(.borderedProminent)
    }
  }

}

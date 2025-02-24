import SwiftUI

struct LazyView<Content: View>: View {
  let content: Content
  let loadingContent = Text("Loading...")
  let delay = 0.05
  @State private var isLoaded: Bool = false

  init(@ViewBuilder _ content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    if isLoaded {
      content
    } else {
      Text("Loading...")
        .onAppear {
          DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            isLoaded = true
          }
        }
    }
  }
}

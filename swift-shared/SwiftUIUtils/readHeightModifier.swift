import SwiftUI

extension View {
  public func readHeight(_ height: Binding<CGFloat>) -> some View {
    self.modifier(HeightReader(height: height))
  }
}

struct HeightReader: ViewModifier {
  @Binding var height: CGFloat

  func body(content: Content) -> some View {
    content
      .background(
        GeometryReader { proxy in
          Color.clear
            .onAppear {
              height = proxy.size.height
            }
            .onChange(of: proxy.size.height) { oldHeight, newHeight in
              height = newHeight
            }
        }
      )
  }
}

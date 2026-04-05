import SwiftUI

// https://stackoverflow.com/questions/57467353/conditional-property-in-swiftui
// Not ideal for animations: https://www.objc.io/blog/2021/08/24/conditional-view-modifiers/
extension View {
  @ViewBuilder
  public func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View
  {
    if condition { transform(self) } else { self }
  }
}

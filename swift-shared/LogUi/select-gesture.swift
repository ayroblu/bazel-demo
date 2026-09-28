import SwiftUI

enum SelectDragState {
  case began, changed, ended
}

extension View {
  /// Hold, then drag to select. A SwiftUI drag inside a ScrollView blocks the scroll view's pan
  /// on iOS 18 even as a simultaneous gesture; UIKit's long press recogniser is exclusive with
  /// the pan instead. macOS gets tap-to-select only.
  func selectDragGesture(space: String, onChange: @escaping (SelectDragState, CGPoint) -> Void)
    -> some View
  {
    #if canImport(UIKit)
      gesture(SelectGesture(space: space, onChange: onChange))
    #else
      self
    #endif
  }
}

#if canImport(UIKit)
  import UIKit

  private struct SelectGesture: UIGestureRecognizerRepresentable {
    let space: String
    let onChange: (SelectDragState, CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
      let recognizer = UILongPressGestureRecognizer()
      recognizer.minimumPressDuration = 0.3
      return recognizer
    }

    func handleUIGestureRecognizerAction(
      _ recognizer: UILongPressGestureRecognizer, context: Context
    ) {
      let state: SelectDragState =
        switch recognizer.state {
        case .began: .began
        case .changed: .changed
        default: .ended
        }
      onChange(state, context.converter.location(in: .named(space)))
    }
  }
#endif

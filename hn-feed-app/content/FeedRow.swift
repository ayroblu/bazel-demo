import SwiftUI
import UIKit
import feed

struct FeedRow: View {
  let item: FeedItem

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Button {
        openInApp(item.link)
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          Text(item.title)
            .font(.body)
            .foregroundStyle(.primary)
          Text(displayURL)
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(byline)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .prewarmOnTouchDown(item.link)

      if item.link != item.hnlink {
        Button {
          openInApp(item.hnlink)
        } label: {
          Image(systemName: "bubble.left")
            .foregroundStyle(.orange)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .prewarmOnTouchDown(item.hnlink)
        .accessibilityLabel("Comments")
      }
    }
  }

  private var displayURL: String {
    let url = item.link.absoluteString.replacing(/^https?:\/\//, with: "")
    return url.removingPercentEncoding ?? url
  }

  private var byline: String {
    let age = item.ts.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    return [item.author, age].compactMap { $0 }.joined(separator: " · ")
  }
}

extension View {
  fileprivate func prewarmOnTouchDown(_ url: URL) -> some View {
    buttonStyle(.plain).gesture(TouchDownGesture { prewarm(url) })
  }
}

private struct TouchDownGesture: UIGestureRecognizerRepresentable {
  let action: () -> Void

  func makeUIGestureRecognizer(context: Context) -> TouchDownRecognizer {
    TouchDownRecognizer()
  }

  func updateUIGestureRecognizer(_ recognizer: TouchDownRecognizer, context: Context) {
    recognizer.onTouchDown = action
  }
}

private final class TouchDownRecognizer: UIGestureRecognizer {
  var onTouchDown: (() -> Void)?

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    onTouchDown?()
    state = .failed
  }
}

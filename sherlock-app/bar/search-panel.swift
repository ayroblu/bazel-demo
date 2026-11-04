import AppKit

final class SearchPanel: NSPanel {
  var onKeyEquivalent: (NSEvent) -> Bool = { _ in false }

  init() {
    super.init(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered, defer: false)
    isFloatingPanel = true
    level = .popUpMenu
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    backgroundColor = .clear
    isOpaque = false
    hasShadow = true
    hidesOnDeactivate = false
    becomesKeyOnlyIfNeeded = false
    animationBehavior = .none
  }

  override var canBecomeKey: Bool { true }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    onKeyEquivalent(event) || super.performKeyEquivalent(with: event)
  }
}

final class FlippedView: NSView {
  override var isFlipped: Bool { true }
}

nonisolated enum Layout {
  static let width: CGFloat = 680
  static let searchHeight: CGFloat = 64
  static let rowHeight: CGFloat = 50
  static let maxRows = 9
  static let padding: CGFloat = 8
  static let cornerRadius: CGFloat = 14
  static let logoSize: CGFloat = 40
  static let iconSize: CGFloat = 36
}

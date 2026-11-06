import AppKit

final class AnswerView: NSView {
  private let scrollView = NSScrollView()
  private let content = FlippedView()
  private let body = NSTextField(wrappingLabelWithString: "")
  private let spinner = NSProgressIndicator()
  private let footer = NSTextField(wrappingLabelWithString: "")

  override var isFlipped: Bool { true }

  init(width: CGFloat) {
    super.init(frame: NSRect(x: 0, y: 0, width: width, height: 0))
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    body.font = .systemFont(ofSize: 15)
    content.addSubview(body)
    scrollView.documentView = content
    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.isDisplayedWhenStopped = false
    footer.font = .systemFont(ofSize: 13)
    footer.isSelectable = false
    for view in [scrollView, spinner, footer] {
      addSubview(view)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  func show(_ text: String, color: NSColor, status: String?, maxHeight: CGFloat) -> CGFloat {
    let width = bounds.width
    body.stringValue = text
    body.textColor = color
    let textWidth = width - 26
    let textHeight = body.cell!.cellSize(
      forBounds: NSRect(x: 0, y: 0, width: textWidth, height: .greatestFiniteMagnitude)
    ).height
    body.frame = NSRect(x: 13, y: 8, width: textWidth, height: textHeight)
    content.frame = NSRect(x: 0, y: 0, width: width, height: textHeight + 16)
    let footerX: CGFloat = status == nil ? 13 : 34
    let footerWidth = width - footerX - 13
    footer.stringValue = status ?? "↩ Copy   ⎋ Back"
    let footerHeight = footer.cell!.cellSize(
      forBounds: NSRect(x: 0, y: 0, width: footerWidth, height: .greatestFiniteMagnitude)
    ).height
    let scrollHeight =
      text.isEmpty ? 0 : min(content.frame.height, maxHeight - footerHeight - footerPadding)
    scrollView.frame = NSRect(x: 0, y: 0, width: width, height: scrollHeight)
    spinner.frame = NSRect(x: 13, y: scrollHeight + 4, width: 16, height: 16)
    footer.frame = NSRect(x: footerX, y: scrollHeight + 4, width: footerWidth, height: footerHeight)
    if status == nil {
      spinner.stopAnimation(nil)
    } else {
      spinner.startAnimation(nil)
    }
    frame.size.height = scrollHeight + footerHeight + footerPadding
    return frame.height
  }

  func stopSpinner() {
    spinner.stopAnimation(nil)
  }
}

private let footerPadding: CGFloat = 8

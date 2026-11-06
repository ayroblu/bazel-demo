import AppKit
import search

final class IconCache {
  private var icons: [ResultItem.Icon: NSImage] = [:]
  private var prewarmed: Set<ResultItem.Icon> = []

  func image(for icon: ResultItem.Icon) -> NSImage {
    if let image = icons[icon] { return image }
    let image =
      switch icon {
      case .file(let path):
        NSWorkspace.shared.icon(forFile: (path as NSString).resolvingSymlinksInPath)
      case .symbol(let name):
        (NSImage(systemSymbolName: name, accessibilityDescription: nil)
          ?? NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil)!)
          .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .medium))!
      case .image(let path):
        thumbnail(path)
      case .favicon(let data, let badge):
        badged(data, badge: image(for: .file(badge)))
      case .text(let text):
        textIcon(text)
      }
    icons[icon] = image
    return image
  }

  func prewarm(_ paths: [String]) {
    let missing = Set(paths).filter { !prewarmed.contains(.file($0)) }
    guard !missing.isEmpty else { return }
    Task {
      let size = NSSize(width: Layout.iconSize, height: Layout.iconSize)
      for (path, image) in await renderIcons(Array(missing)) {
        icons[.file(path)] = NSImage(cgImage: image, size: size)
        prewarmed.insert(.file(path))
      }
    }
  }

  func trim() {
    icons = icons.filter { prewarmed.contains($0.key) || isSymbol($0.key) }
  }
}

private func isSymbol(_ icon: ResultItem.Icon) -> Bool {
  guard case .symbol = icon else { return false }
  return true
}

private func thumbnail(_ path: String) -> NSImage {
  let options = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceThumbnailMaxPixelSize: Int(Layout.iconSize * 2),
    kCGImageSourceCreateThumbnailWithTransform: true,
  ] as CFDictionary
  guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
    let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
  else { return NSImage(systemSymbolName: "photo", accessibilityDescription: nil)! }
  return NSImage(cgImage: image, size: NSSize(width: Layout.iconSize, height: Layout.iconSize))
}

private func badged(_ favicon: Data, badge: NSImage) -> NSImage {
  guard let face = NSImage(data: favicon) else { return badge }
  let pixels = Int(Layout.iconSize * 2)
  let size = CGFloat(pixels)
  let context = CGContext(
    data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
  NSGraphicsContext.current?.imageInterpolation = .high
  let faceFrame = NSRect(x: size * 0.06, y: size * 0.17, width: size * 0.77, height: size * 0.77)
  NSGraphicsContext.saveGraphicsState()
  NSBezierPath(
    roundedRect: faceFrame, xRadius: faceFrame.width * 0.2, yRadius: faceFrame.width * 0.2
  ).addClip()
  face.draw(in: faceFrame)
  NSGraphicsContext.restoreGraphicsState()
  badge.draw(in: NSRect(x: size * 0.5, y: 0, width: size * 0.5, height: size * 0.5))
  NSGraphicsContext.restoreGraphicsState()
  return NSImage(
    cgImage: context.makeImage()!, size: NSSize(width: Layout.iconSize, height: Layout.iconSize))
}

private func textIcon(_ text: String) -> NSImage {
  NSImage(size: NSSize(width: Layout.iconSize, height: Layout.iconSize), flipped: false) { rect in
    let fitted = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 26)])
    let fontSize = 26 * min(1, rect.width / fitted.size().width)
    let string = NSAttributedString(
      string: text,
      attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.labelColor])
    let size = string.size()
    string.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    return true
  }
}

@concurrent private func renderIcons(_ paths: [String]) async -> [(String, CGImage)] {
  let pixels = Int(Layout.iconSize * 2)
  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
  return paths.compactMap { path in
    let icon = NSWorkspace.shared.icon(forFile: (path as NSString).resolvingSymlinksInPath)
    let context = CGContext(
      data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage().map { (path, $0) }
  }
}

import AppKit
import search

final class IconCache {
  private var icons: [ResultItem.Icon: NSImage] = [:]

  func image(for icon: ResultItem.Icon) -> NSImage {
    if let image = icons[icon] { return image }
    let image =
      switch icon {
      case .file(let path):
        NSWorkspace.shared.icon(forFile: (path as NSString).resolvingSymlinksInPath)
      case .symbol(let name):
        NSImage(systemSymbolName: name, accessibilityDescription: nil)!
          .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .medium))!
      }
    icons[icon] = image
    return image
  }

  func prewarm(_ paths: [String]) {
    let missing = paths.filter { icons[.file($0)] == nil }
    guard !missing.isEmpty else { return }
    Task {
      let size = NSSize(width: Layout.iconSize, height: Layout.iconSize)
      for (path, image) in await renderIcons(missing) {
        icons[.file(path)] = NSImage(cgImage: image, size: size)
      }
    }
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

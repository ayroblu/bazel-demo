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

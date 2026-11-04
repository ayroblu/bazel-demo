import AppKit

final class Favicons {
  var onUpdate: () -> Void = {}
  private var fetching: Set<String> = []

  func icon(for url: URL, fallback: @autoclosure () -> ResultItem.Icon) -> ResultItem.Icon {
    guard let page = homePage(of: url), let host = page.host() else { return fallback() }
    let file = faviconsURL.appending(path: host + ".png")
    let failure = faviconsURL.appending(path: host + ".none")
    let canRetry = (age(of: failure) ?? .infinity) > retryAge
    if let age = age(of: file) {
      if age > refreshAge, canRetry {
        fetch(page, host: host)
      }
      return .image(file.path)
    }
    if canRetry {
      fetch(page, host: host)
    }
    return fallback()
  }

  private func fetch(_ page: URL, host: String) {
    guard fetching.insert(host).inserted else { return }
    Task {
      let png = await fetchFavicon(page)
      try? FileManager.default.createDirectory(at: faviconsURL, withIntermediateDirectories: true)
      if let png {
        try? png.write(to: faviconsURL.appending(path: host + ".png"), options: .atomic)
      } else {
        try? Data().write(to: faviconsURL.appending(path: host + ".none"))
      }
      fetching.remove(host)
      if png != nil {
        onUpdate()
      }
    }
  }
}

private func homePage(of url: URL) -> URL? {
  guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
    let scheme = components.scheme, ["http", "https"].contains(scheme), components.host != nil
  else { return nil }
  components.path = "/"
  components.query = nil
  components.fragment = nil
  components.user = nil
  components.password = nil
  return components.url
}

private let faviconsURL = URL.cachesDirectory.appending(path: "com.ayroblu.sherlock/Favicons")

private let refreshAge: TimeInterval = 30 * 24 * 60 * 60

private let retryAge: TimeInterval = 24 * 60 * 60

private func age(of file: URL) -> TimeInterval? {
  ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date)
    .map { -$0.timeIntervalSinceNow }
}

@concurrent private func fetchFavicon(_ page: URL) async -> Data? {
  var candidates: [URL] = []
  if let (data, response) = try? await session.data(from: page) {
    let html = String(decoding: data.prefix(300_000), as: UTF8.self)
    candidates = iconLinks(in: html, base: response.url ?? page)
  }
  candidates.append(URL(string: "/favicon.ico", relativeTo: page)!.absoluteURL)
  for candidate in candidates {
    guard let (data, response) = try? await session.data(from: candidate),
      (response as? HTTPURLResponse)?.statusCode == 200,
      let png = renderPNG(data)
    else { continue }
    return png
  }
  return nil
}

private nonisolated let session: URLSession = {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.timeoutIntervalForRequest = 8
  configuration.httpAdditionalHeaders = [
    "User-Agent":
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
  ]
  return URLSession(configuration: configuration)
}()

private nonisolated func iconLinks(in html: String, base: URL) -> [URL] {
  var links: [(url: URL, size: Int)] = []
  for tag in html.matches(of: /<link\b[^>]*>/.ignoresCase()) {
    let text = String(tag.output)
    guard let rel = attribute("rel", in: text)?.lowercased(), rel.contains("icon"),
      !rel.contains("mask"), let href = attribute("href", in: text),
      let url = URL(string: href, relativeTo: base)?.absoluteURL
    else { continue }
    let declared = attribute("sizes", in: text)?.split(separator: "x").first.flatMap { Int($0) }
    links.append((url, declared ?? (rel.contains("apple-touch-icon") ? 180 : 16)))
  }
  return links.sorted { $0.size > $1.size }.map(\.url)
}

private nonisolated func attribute(_ name: String, in tag: String) -> String? {
  let pattern = try! Regex("\\b\(name)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)").ignoresCase()
  guard let match = tag.firstMatch(of: pattern),
    let value = match.output[1].substring
  else { return nil }
  return String(value).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    .replacingOccurrences(of: "&amp;", with: "&")
}

private nonisolated func renderPNG(_ data: Data) -> Data? {
  guard let image = NSImage(data: data), image.isValid, image.size.width > 0 else { return nil }
  let pixels = 64
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)
  else { return nil }
  let frame = NSRect(x: 0, y: 0, width: pixels, height: pixels).insetBy(dx: 6, dy: 6)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  NSGraphicsContext.current?.imageInterpolation = .high
  NSBezierPath(roundedRect: frame, xRadius: 11, yRadius: 11).addClip()
  image.draw(in: frame)
  NSGraphicsContext.restoreGraphicsState()
  return bitmap.representation(using: .png, properties: [:])
}

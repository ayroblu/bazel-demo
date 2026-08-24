import Foundation

public struct FuriganaSegment: Equatable, Sendable {
  public let text: String
  public let reading: String?

  public init(text: String, reading: String? = nil) {
    self.text = text
    self.reading = reading
  }
}

public enum FuriganaParser {
  public static func parse(_ source: String) -> [FuriganaSegment] {
    var segments: [FuriganaSegment] = []
    var plain = ""
    var base = ""
    var reading = ""
    var insideReading = false

    func flushPlain() {
      if !plain.isEmpty {
        segments.append(FuriganaSegment(text: plain))
        plain = ""
      }
    }

    for character in source {
      if character == "[", !insideReading {
        if let range = plain.range(of: #"[\p{Han}々〆ヵヶ]+$"#, options: .regularExpression) {
          base = String(plain[range])
          plain.removeSubrange(range)
          flushPlain()
          insideReading = true
        } else {
          plain.append(character)
        }
      } else if character == "]", insideReading {
        if !base.isEmpty, !reading.isEmpty {
          segments.append(FuriganaSegment(text: base, reading: reading))
        } else {
          plain += base + "[" + reading + "]"
        }
        base = ""
        reading = ""
        insideReading = false
      } else if insideReading {
        reading.append(character)
      } else {
        plain.append(character)
      }
    }

    if insideReading {
      plain += base + "[" + reading
    }
    flushPlain()
    return segments
  }

  public static func displayText(_ source: String) -> String {
    parse(source).map(\.text).joined()
  }

  public static func speechText(_ source: String) -> String {
    parse(source).map { $0.reading ?? $0.text }.joined()
  }
}

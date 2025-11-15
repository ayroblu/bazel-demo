import Foundation

extension String {
  public func trim() -> String {
    return self.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func dropEmpty() -> String? {
    return self.trim() == "" ? nil : self
  }
}

extension Substring {
  public func trim() -> String {
    return self.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

extension Array where Element == NSValue {
  public func extractRanges(in string: String) -> [Range<String.Index>] {
    let swiftRanges: [Range<String.Index>] = self.compactMap { value in
      let nsRange = value.rangeValue
      guard let swiftRange = Range(nsRange, in: string) else {
        return nil
      }
      return swiftRange
    }

    return swiftRanges
  }
}

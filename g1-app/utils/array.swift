extension Array {
  public subscript(safe index: Int) -> Element? {
    return indices.contains(index) ? self[index] : nil
  }
}

extension Sequence where Element: Hashable {
  public func uniqued() -> [Element] {
    var set = Set<Element>()
    return filter { set.insert($0).inserted }
  }
}

extension Array where Element: Identifiable {
  public func uniq() -> [Element] {
    var seenSet = Set<Element.ID>()
    return filter { seenSet.insert($0.id).inserted }
  }
}

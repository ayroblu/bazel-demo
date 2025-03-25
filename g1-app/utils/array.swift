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

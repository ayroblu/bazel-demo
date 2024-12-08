extension String {
  public func indentSpaces(count: Int) -> String {
    return indentMultilineString(self, with: String(repeating: " ", count: count))
  }
  public func splitlines() -> [Substring] {
    return self.split(separator: "\n")
  }
}
func indentMultilineString(_ string: String, with indentation: String) -> String {
  return
    string
    .split(separator: "\n")
    .map { "\(indentation)\($0)" }
    .joined(separator: "\n")
}

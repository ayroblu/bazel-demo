import Foundation

nonisolated struct SearchQuery: Sendable {
  let text: String
  let scalars: [Unicode.Scalar]
  let words: [[Unicode.Scalar]]
  let compact: [Unicode.Scalar]
  let mask: UInt64

  init(_ raw: String) {
    let words = fold(raw).split(whereSeparator: \.isWhitespace).map(String.init)
    text = words.joined(separator: " ")
    scalars = Array(text.unicodeScalars)
    self.words = words.map { Array($0.unicodeScalars) }
    compact = Array(words.joined().unicodeScalars)
    mask = characterMask(compact)
  }

  var isEmpty: Bool { scalars.isEmpty }
}

nonisolated struct SearchName: Sendable {
  let scalars: [Unicode.Scalar]
  let wordStarts: [Bool]
  let mask: UInt64

  init(_ name: String) {
    let original = Array(name.unicodeScalars)
    scalars = Array(fold(name).unicodeScalars)
    mask = characterMask(scalars)
    let sameLength = original.count == scalars.count
    var starts = [Bool](repeating: false, count: scalars.count)
    for i in scalars.indices {
      guard isWordCharacter(scalars[i]) else { continue }
      starts[i] =
        i == 0 || !isWordCharacter(scalars[i - 1])
        || (sameLength && original[i].properties.isUppercase
          && original[i - 1].properties.isLowercase)
    }
    wordStarts = starts
  }
}

nonisolated func score(_ query: SearchQuery, _ name: SearchName, fuzzy: Bool = true) -> Int? {
  guard query.mask & ~name.mask == 0 else { return nil }
  let text = query.scalars
  let scalars = name.scalars
  if scalars == text { return 1000 }
  if scalars.starts(with: text) { return 900 }
  if hasWordPrefix(name, text) { return 800 }
  if query.words.count > 1, query.words.allSatisfy({ hasWordPrefix(name, $0) }) { return 750 }
  if matchesInitials(name, query.compact) { return 700 }
  if !indices(of: text, in: scalars).isEmpty { return 600 }
  guard fuzzy, name.scalars.count <= maxFuzzyLength else { return nil }
  return fuzzyScore(name, query.compact).map { 100 + $0 }
}

nonisolated func fold(_ string: String) -> String {
  string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
}

nonisolated func searchNames(_ names: String...) -> [SearchName] {
  var seen = Set<String>()
  var result: [SearchName] = []
  for name in names {
    let compact = String(name.unicodeScalars.filter { isWordCharacter($0) || $0 == " " })
    for variant in [name, compact] where seen.insert(variant).inserted {
      result.append(SearchName(variant))
    }
  }
  return result
}

private nonisolated let maxFuzzyLength = 40

private nonisolated func characterMask(_ scalars: [Unicode.Scalar]) -> UInt64 {
  scalars.reduce(0) { mask, scalar in
    switch scalar {
    case "a"..."z": mask | 1 << (scalar.value - 97)
    case "0"..."9": mask | 1 << (scalar.value - 48 + 26)
    case " ": mask
    default: mask | 1 << 63
    }
  }
}

private nonisolated func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
  scalar.properties.isAlphabetic || scalar.properties.numericType != nil
}

private nonisolated func hasWordPrefix(_ name: SearchName, _ text: [Unicode.Scalar]) -> Bool {
  indices(of: text, in: name.scalars).contains { name.wordStarts[$0] }
}

private nonisolated func indices(
  of text: [Unicode.Scalar], in scalars: [Unicode.Scalar]
) -> some Collection<Int> {
  let last = scalars.count - text.count
  return (0..<max(last + 1, 0)).lazy.filter { start in
    var offset = 0
    while offset < text.count, scalars[start + offset] == text[offset] {
      offset += 1
    }
    return offset == text.count
  }
}

private nonisolated func matchesInitials(_ name: SearchName, _ compact: [Unicode.Scalar]) -> Bool {
  guard compact.count >= 2 else { return false }
  let initials = name.scalars.indices.lazy.filter { name.wordStarts[$0] }.map { name.scalars[$0] }
  return initials.starts(with: compact)
}

private nonisolated func fuzzyScore(_ name: SearchName, _ compact: [Unicode.Scalar]) -> Int? {
  var total = 0
  var queryIndex = 0
  var previousMatch: Int?
  for (i, scalar) in name.scalars.enumerated() where queryIndex < compact.count {
    guard scalar == compact[queryIndex] else { continue }
    if queryIndex == 0, !name.wordStarts[i] { continue }
    if name.wordStarts[i] { total += 8 }
    if let previousMatch { total += previousMatch == i - 1 ? 4 : -1 }
    previousMatch = i
    queryIndex += 1
  }
  guard queryIndex == compact.count else { return nil }
  return min(max(total, 0), 499)
}

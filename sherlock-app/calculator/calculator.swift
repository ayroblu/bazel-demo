import Foundation

public func calculate(_ input: String) -> Double? {
  var parser = Parser(input.unicodeScalars.filter { !$0.properties.isWhitespace })
  guard let value = parser.parseExpression(), parser.isAtEnd, parser.hasOperation,
    value.isFinite
  else { return nil }
  return value
}

private struct Parser {
  private let scalars: [Unicode.Scalar]
  private var index = 0
  private(set) var hasOperation = false

  init(_ scalars: [Unicode.Scalar]) {
    self.scalars = scalars
  }

  var isAtEnd: Bool { index == scalars.count }

  mutating func parseExpression() -> Double? {
    guard var value = parseTerm() else { return nil }
    while let symbol = peek(), symbol == "+" || symbol == "-" {
      advance()
      guard let right = parseTerm() else { return nil }
      value = symbol == "+" ? value + right : value - right
      hasOperation = true
    }
    return value
  }

  private mutating func parseTerm() -> Double? {
    guard var value = parseUnary() else { return nil }
    while let symbol = peek(), "*×/÷".unicodeScalars.contains(symbol) {
      advance()
      guard let right = parseUnary() else { return nil }
      value = symbol == "*" || symbol == "×" ? value * right : value / right
      hasOperation = true
    }
    return value
  }

  private mutating func parseUnary() -> Double? {
    switch peek() {
    case "-":
      advance()
      return parseUnary().map { -$0 }
    case "+":
      advance()
      return parseUnary()
    default:
      return parsePower()
    }
  }

  private mutating func parsePower() -> Double? {
    guard let base = parsePercent() else { return nil }
    guard peek() == "^" else { return base }
    advance()
    hasOperation = true
    return parseUnary().map { pow(base, $0) }
  }

  private mutating func parsePercent() -> Double? {
    guard var value = parsePrimary() else { return nil }
    while peek() == "%" {
      advance()
      value /= 100
      hasOperation = true
    }
    return value
  }

  private mutating func parsePrimary() -> Double? {
    guard let symbol = peek() else { return nil }
    if symbol == "(" {
      advance()
      return parseClosingParenthesis(parseExpression())
    }
    if isDigit(symbol) || symbol == "." {
      return parseNumber()
    }
    if symbol.properties.isAlphabetic {
      return parseName()
    }
    return nil
  }

  private mutating func parseNumber() -> Double? {
    let start = index
    while let symbol = peek(), isDigit(symbol) || symbol == "." {
      advance()
    }
    return Double(String(String.UnicodeScalarView(scalars[start..<index])))
  }

  private mutating func parseName() -> Double? {
    let start = index
    while let symbol = peek(), symbol.properties.isAlphabetic || isDigit(symbol) {
      advance()
    }
    let name = String(String.UnicodeScalarView(scalars[start..<index])).lowercased()
    if let constant = constants[name] { return constant }
    guard let function = functions[name], peek() == "(" else { return nil }
    advance()
    hasOperation = true
    return parseClosingParenthesis(parseExpression()).map(function)
  }

  private mutating func parseClosingParenthesis(_ value: Double?) -> Double? {
    guard let value, peek() == ")" else { return nil }
    advance()
    return value
  }

  private func peek() -> Unicode.Scalar? {
    index < scalars.count ? scalars[index] : nil
  }

  private mutating func advance() {
    index += 1
  }
}

private func isDigit(_ scalar: Unicode.Scalar) -> Bool {
  ("0"..."9").contains(scalar)
}

private let constants: [String: Double] = ["pi": .pi, "π": .pi, "e": M_E]

private let functions: [String: @Sendable (Double) -> Double] = [
  "sqrt": { sqrt($0) }, "abs": { abs($0) }, "sin": { sin($0) }, "cos": { cos($0) },
  "tan": { tan($0) }, "asin": { asin($0) }, "acos": { acos($0) }, "atan": { atan($0) },
  "ln": { log($0) }, "log": { log10($0) }, "log2": { log2($0) }, "exp": { exp($0) },
  "round": { $0.rounded() }, "floor": { floor($0) }, "ceil": { ceil($0) },
]

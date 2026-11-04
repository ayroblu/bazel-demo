import Foundation
import calculator

func calculation(_ text: String) -> ResultItem? {
  let expression = text.hasPrefix("=") ? String(text.dropFirst()) : text
  guard let value = calculate(expression) else { return nil }
  let copied = format(value, grouping: false)
  return ResultItem(
    id: "calculator", title: format(value, grouping: true),
    subtitle: "Copy \(copied) to the clipboard", icon: .file(calculatorPath),
    action: .copy(copied))
}

private func format(_ value: Double, grouping: Bool) -> String {
  let formatter = NumberFormatter()
  let magnitude = abs(value)
  formatter.numberStyle = magnitude != 0 && (magnitude >= 1e15 || magnitude < 1e-9) ? .scientific : .decimal
  formatter.maximumFractionDigits = 10
  formatter.usesGroupingSeparator = grouping
  return formatter.string(from: NSNumber(value: value)) ?? String(value)
}

private let calculatorPath = "/System/Applications/Calculator.app"

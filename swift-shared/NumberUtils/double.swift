import Foundation

extension Double {
  public func toFixed(_ significantFigures: Int) -> String {
    return String(format: "%.\(significantFigures)f", self)
  }
  public init(_ from: Decimal) {
    self.init(from.doubleValue)
  }
}
extension Decimal {
  public var doubleValue: Double {
    (self as NSDecimalNumber).doubleValue
  }
}

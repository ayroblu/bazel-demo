// precedencegroup PowerPrecedence {
//   higherThan: MultiplicationPrecedence
// }
// infix operator ** : PowerPrecedence
// func ** (radix: Int, power: Int) -> Int {
//   return Int(pow(Double(radix), Double(power)))
// }
extension Int {
  func squared() -> Int {
    return self * self
  }
}

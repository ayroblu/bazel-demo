import CoreBluetooth
import SwiftData

struct LeftRight {
  let left: CBPeripheral?
  let right: CBPeripheral?
}
class Pairing {
  var paired: [String: LeftRight] = [:]
  let modelContext: ModelContext
  let connect: (CBPeripheral, CBPeripheral) -> Void

  init(
    modelContext: ModelContext, connect: @escaping (CBPeripheral, CBPeripheral) -> Void
  ) {
    self.modelContext = modelContext
    self.connect = connect
  }

  func onPeripheral(peripheral: CBPeripheral) -> Bool {
    guard let name = peripheral.name else { return false }
    guard name.contains("Even G1") else { return false }

    let components = name.components(separatedBy: "_")
    guard components.count > 1, let channelNumber = components[safe: 1] else { return false }
    if let lr = paired[channelNumber] {
      if let right = lr.right, name.contains("_L_") {
        connect(peripheral, right)
        return true
      }
      if let left = lr.left, name.contains("_R_") {
        connect(left, peripheral)
        return true
      }
    } else {
      if name.contains("_L_") {
        paired[channelNumber] = LeftRight(left: peripheral, right: nil)
      } else if name.contains("_R_") {
        paired[channelNumber] = LeftRight(left: nil, right: peripheral)
      }
    }
    return false
  }
}

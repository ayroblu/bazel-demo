import CoreBluetooth
import Log
import jotai

extension BluetoothManager {
  func syncUnknown() {
    let pairing = Pairing(connect: connect)
    self.pairing = pairing

    startPairingScan()
  }

  private func startPairingScan() {
    guard let pairing else { return }
    let peripherals = manager.retrieveConnectedPeripherals(withServices: [
      uartServiceCbuuid
    ])
    for peripheral in peripherals {
      if pairing.onPeripheral(peripheral: peripheral) {
        return
      }
    }
    log("No paired peripherals found")
    // manager.scanForPeripherals(withServices: [uartServiceCbuuid])
    manager.scanForPeripherals(withServices: nil)
  }

  func stopPairing() {
    if pairing != nil {
      pairing = nil
    }
    manager.stopScan()
  }
}

struct LeftRight {
  let left: CBPeripheral?
  let right: CBPeripheral?
}
class Pairing {
  var paired: [String: LeftRight] = [:]
  let connect: (CBPeripheral, CBPeripheral) -> Void

  init(connect: @escaping (CBPeripheral, CBPeripheral) -> Void) {
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

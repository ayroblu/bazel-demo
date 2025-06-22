import CoreBluetooth
import Log
import jotai

extension BluetoothManager {
  public func syncUnknown() {
    let pairing = Pairing(connect: manager.connect)
    manager.pairing = pairing

    startPairingScan()
  }

  private func startPairingScan() {
    guard let pairing = manager.pairing else { return }
    let peripherals = manager.manager.retrieveConnectedPeripherals(withServices: [
      manager.uartServiceCbuuid
    ])
    for peripheral in peripherals {
      if pairing.onPeripheral(peripheral: peripheral) {
        return
      }
    }
    log("No paired peripherals found")
    // manager.scanForPeripherals(withServices: [uartServiceCbuuid])
    manager.manager.scanForPeripherals(withServices: nil)
  }

  public func stopPairing() {
    if manager.pairing != nil {
      manager.pairing = nil
    }
    manager.manager.stopScan()
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

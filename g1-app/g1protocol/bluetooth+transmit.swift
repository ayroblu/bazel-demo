import CoreBluetooth
import Log
import jotai

extension BluetoothManager {
  func transmitBoth(_ data: Data) {
    guard let left = leftPeripheral else { return }
    guard let right = rightPeripheral else { return }
    transmit(data, for: left, type: .withoutResponse)
    transmit(data, for: right, type: .withoutResponse)
  }
  func transmitRight(_ data: Data) {
    guard let right = rightPeripheral else { return }
    transmit(data, for: right, type: .withoutResponse)
  }
  func readBoth(_ data: Data) {
    guard let left = leftPeripheral else { return }
    guard let right = rightPeripheral else { return }
    transmit(data, for: left, type: .withResponse)
    transmit(data, for: right, type: .withResponse)
  }
  func readLeft(_ data: Data) {
    guard let left = leftPeripheral else { return }
    transmit(data, for: left, type: .withResponse)
  }
  func readRight(_ data: Data) {
    guard let right = rightPeripheral else { return }
    transmit(data, for: right, type: .withResponse)
  }
  func transmit(_ data: Data, for peripheral: CBPeripheral, type: CBCharacteristicWriteType) {
    guard let name = peripheral.name else { return }
    guard
      let characteristic = name.contains("_L_")
        ? transmitLeftCharacteristic : transmitRightCharacteristic
    else { return }
    peripheral.writeValue(data, for: characteristic, type: type)
  }
}

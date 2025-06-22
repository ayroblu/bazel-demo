import CoreBluetooth
import Log
import jotai

extension BluetoothManager {
  public func transmitBoth(_ data: Data) {
    guard let left = manager.leftPeripheral else { return }
    guard let right = manager.rightPeripheral else { return }
    transmit(data, for: left, type: .withoutResponse)
    transmit(data, for: right, type: .withoutResponse)
  }
  public func transmitRight(_ data: Data) {
    guard let right = manager.rightPeripheral else { return }
    transmit(data, for: right, type: .withoutResponse)
  }
  public func readBoth(_ data: Data) {
    guard let left = manager.leftPeripheral else { return }
    guard let right = manager.rightPeripheral else { return }
    transmit(data, for: left, type: .withResponse)
    transmit(data, for: right, type: .withResponse)
  }
  public func readLeft(_ data: Data) {
    guard let left = manager.leftPeripheral else { return }
    transmit(data, for: left, type: .withResponse)
  }
  public func readRight(_ data: Data) {
    guard let right = manager.rightPeripheral else { return }
    transmit(data, for: right, type: .withResponse)
  }
  public func transmit(_ data: Data, for peripheral: CBPeripheral, type: CBCharacteristicWriteType) {
    guard let name = peripheral.name else { return }
    guard
      let characteristic = name.contains("_L_")
        ? manager.transmitLeftCharacteristic : manager.transmitRightCharacteristic
    else { return }
    peripheral.writeValue(data, for: characteristic, type: type)
  }
}

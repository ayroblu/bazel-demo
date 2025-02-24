import CoreBluetooth
import Log

class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  let uartServiceCbuuid = CBUUID(string: uartServiceUuid)
  let uartTxCharacteristicCbuuid = CBUUID(string: uartTxCharacteristicUuid)
  let uartRxCharacteristicCbuuid = CBUUID(string: uartRxCharacteristicUuid)
  let smpServiceCbuuid = CBUUID(string: smpServiceUuid)
  let smpCharacteristicCbuuid = CBUUID(string: smpCharacteristicUuid)
  let discoverSmb = false
  var manager: ConnectionManager?

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn:
      log("Bluetooth is powered on.")
    case .poweredOff:
      log("Bluetooth is powered off.")
    default:
      log("Bluetooth state is unknown or unsupported.")
    }
  }

  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    guard let name = peripheral.name else { return }
    log("discovered \(name)")
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard let name = peripheral.name else { return }
    log("didConnect \(name)")
    // peripheral.discoverServices(nil)
    if discoverSmb {
      peripheral.discoverServices([uartServiceCbuuid, smpServiceCbuuid])
    } else {
      peripheral.discoverServices([uartServiceCbuuid])
    }
  }

  func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    guard let name = peripheral.name else { return }
    log("didFailToConnect \(name)", error ?? "")
  }

  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    guard let name = peripheral.name else { return }
    log("didDisconnectPeripheral \(name)", error ?? "")
  }

  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
    timestamp: CFAbsoluteTime, isReconnecting: Bool, error: Error?
  ) {
    guard let name = peripheral.name else { return }
    log(
      "didDisconnectPeripheral \(name) ts: \(timestamp) isReconnecting: \(isReconnecting)",
      error ?? "")
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let error = error {
      log("didDiscoverServices error", error)
      return
    }
    guard let services = peripheral.services else { return }

    for service in services {
      if service.uuid == uartServiceCbuuid {
        peripheral.discoverCharacteristics(nil, for: service)
      } else if service.uuid == smpServiceCbuuid {
        if discoverSmb {
          peripheral.discoverCharacteristics(nil, for: service)
        }
      } else {
        log("discover unknown service: \(service)")
      }
    }
  }

  var leftPeripheral: CBPeripheral?
  var rightPeripheral: CBPeripheral?
  var transmitLeftCharacteristic: CBCharacteristic?
  var transmitRightCharacteristic: CBCharacteristic?

  func transmitBoth(_ data: Data) {
    guard let left = leftPeripheral else { return }
    guard let right = rightPeripheral else { return }
    transmit(data, for: left, type: .withoutResponse)
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

  var isConnected = false
  func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) {
    if let error = error {
      log("didDiscoverCharacteristicsFor error", error)
      return
    }
    guard let name = peripheral.name else { return }
    guard let characteristics = service.characteristics else { return }
    if service.uuid.isEqual(uartServiceCbuuid) {
      for characteristic in characteristics {
        switch characteristic.uuid {
        case uartRxCharacteristicCbuuid:
          log("rx \(name)")
          peripheral.setNotifyValue(true, for: characteristic)
        case uartTxCharacteristicCbuuid:
          log("tx \(name)")
          if name.contains("_L_") {
            transmitLeftCharacteristic = characteristic
            leftPeripheral = peripheral
          } else if name.contains("_R_") {
            transmitRightCharacteristic = characteristic
            rightPeripheral = peripheral
          }
        // peripheral.writeValue(
        //   Data([SendCmd.Ping.rawValue, 0x01]), for: characteristic, type: .withoutResponse)
        default:
          log("unknown characteristic")
        }
      }
      guard leftPeripheral != nil else { return }
      guard rightPeripheral != nil else { return }
      guard transmitLeftCharacteristic != nil else { return }
      guard transmitLeftCharacteristic != nil else { return }
      if !isConnected {
        isConnected = true
        manager?.onConnect()
      }
    } else if service.uuid == smpServiceCbuuid && discoverSmb {
      for characteristic in characteristics {
        log("other characteristic for \(name)")
        peripheral.readValue(for: characteristic)
      }
    } else {
      log("-unknown CBService is: \(service)")
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    if let error = error {
      log("didWriteValueFor error", error)
      return
    }
    if characteristic.uuid == uartRxCharacteristicCbuuid {
      peripheral.readValue(for: characteristic)
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard let name = peripheral.name else { return }
    if let error = error {
      log("didUpdateValueFor \(name) error", error, characteristic)
      return
    }
    guard let data: Data = characteristic.value else { return }
    if let service = characteristic.service {
      if service.uuid == smpServiceCbuuid {
        log("smp", name, data.hex)
        return
      } else if service.uuid != uartServiceCbuuid {
        log("unknown", name, data.hex)
        return
      }
    }
    manager?.onValue(peripheral, data: data)
  }

  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    log("willRestoreState", dict)
  }
}

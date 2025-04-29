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
    manager?.mainVm?.isBluetoothEnabled = central.state == .poweredOn
    switch central.state {
    case .poweredOn:
      log("Bluetooth is powered on.")
      restore()
    case .poweredOff:
      log("Bluetooth is powered off.")
    case .unknown:
      break
    case .unsupported:
      break
    case .unauthorized:
      switch CBCentralManager.authorization {
      case .allowedAlways:
        break
      case .denied:
        break
      case .restricted:
        break
      case .notDetermined:
        break
      @unknown default:
        break
      }
    case .resetting:
      break
    @unknown default:
      log("Bluetooth state is unknown.")
    }
  }

  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    guard let name = peripheral.name else { return }
    log("discovered \(name)")
    let _ = manager?.pairing?.onPeripheral(peripheral: peripheral)
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
    manager?.mainVm?.isConnected = false
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
      guard let leftPeripheral else { return }
      guard let rightPeripheral else { return }
      guard transmitLeftCharacteristic != nil else { return }
      guard transmitLeftCharacteristic != nil else { return }
      if !isConnected {
        isConnected = true
        manager?.onConnect()
        manager?.centralManager.registerForConnectionEvents(
          options: [
            CBConnectionEventMatchingOption.peripheralUUIDs: [
              leftPeripheral.identifier.uuidString,
              rightPeripheral.identifier.uuidString,
            ]
          ])
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
    checkConnected()
    onValue(peripheral, data: data, mainVm: manager?.mainVm)
  }

  private func checkConnected() {
    if let leftPeripheral, leftPeripheral.state != .connected {
      log("trying to connect left")
      manager?.centralManager.connect(
        leftPeripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }
    guard let rightPeripheral else {
      log("no right peripheral")
      return
    }
    if rightPeripheral.state != .connected {
      log("trying to connect right")
      manager?.centralManager.connect(
        rightPeripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }
  }
  func centralManager(
    _ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent,
    for peripheral: CBPeripheral
  ) {
    guard let name = peripheral.name else { return }
    // 0 disconnected, 1 connected
    log("connectEventDidOccur", name, event.rawValue)

  }

  var toRestore: [CBPeripheral]?
  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    // log("willRestoreState", dict)
    // kCBRestoredScanServices
    // kCBRestoredPeripherals
    if let peripherals = dict["kCBRestoredPeripherals"] as? [CBPeripheral] {
      toRestore = peripherals
    }
  }
  func restore() {
    if let peripherals = toRestore {
      for peripheral in peripherals {
        if let name = peripheral.name {
          log("restoring", name)
        }
        peripheral.delegate = self
        manager?.centralManager.connect(
          peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
      }
      toRestore = nil
    } else if let glasses = manager?.glasses {
      manager?.reconnectKnown(glasses: glasses)
      manager?.glasses = nil
    }
  }
}

import CoreBluetooth
import Log
import jotai

let uartServiceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
let uartTxCharacteristicUuid = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
let uartRxCharacteristicUuid = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
let smpServiceUuid = "8D53DC1D-1DB7-4CD3-868B-8A527460AA84"
let smpCharacteristicUuid = "DA2E7828-FBCE-4E01-AE9E-261174997C48"

let bluetoothManager = BluetoothManager(store: JotaiStore.shared)

class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  let uartServiceCbuuid = CBUUID(string: uartServiceUuid)
  let uartTxCharacteristicCbuuid = CBUUID(string: uartTxCharacteristicUuid)
  let uartRxCharacteristicCbuuid = CBUUID(string: uartRxCharacteristicUuid)
  let smpServiceCbuuid = CBUUID(string: smpServiceUuid)
  let smpCharacteristicCbuuid = CBUUID(string: smpCharacteristicUuid)
  let discoverSmb = false
  let store: JotaiStore
  var manager: CBCentralManager!

  init(store: JotaiStore) {
    self.store = store
    super.init()
    let options = [CBCentralManagerOptionRestoreIdentifierKey: "central-manager-identifier"]
    manager = CBCentralManager(delegate: self, queue: nil, options: options)
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    store.set(atom: isBluetoothEnabledAtom, value: central.state == .poweredOn)
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
    let _ = pairing?.onPeripheral(peripheral: peripheral)
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
    store.set(atom: isConnectedAtom, value: false)
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
      if !store.get(atom: isConnectedAtom) {
        store.set(atom: isConnectedAtom, value: true)
        if pairing != nil {
          log("onConnect - inserting GlassesModel")
          // TODO:
          // pairing.modelContext.insert(
          //   GlassesModel(left: left.identifier.uuidString, right: right.identifier.uuidString))
          self.pairing = nil
        }
        onConnectListener.executeAll()
        #if os(iOS)
          manager.registerForConnectionEvents(
            options: [
              CBConnectionEventMatchingOption.peripheralUUIDs: [
                leftPeripheral.identifier.uuidString,
                rightPeripheral.identifier.uuidString,
              ]
            ])
        #endif
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
    onValue(peripheral: peripheral, data: data)
  }

  private func checkConnected() {
    if let leftPeripheral, leftPeripheral.state != .connected {
      log("trying to connect left")
      manager.connect(
        leftPeripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }
    guard let rightPeripheral else {
      log("no right peripheral")
      return
    }
    if rightPeripheral.state != .connected {
      log("trying to connect right")
      manager.connect(
        rightPeripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }
  }

  #if os(iOS)
    func centralManager(
      _ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent,
      for peripheral: CBPeripheral
    ) {
      guard let name = peripheral.name else { return }
      // 0 disconnected, 1 connected
      log("connectEventDidOccur", name, event.rawValue)
    }
  #endif

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
        manager.connect(
          peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
      }
      toRestore = nil
    } else if let glasses = waitingGlasses {
      reconnectKnown(glasses: glasses)
      waitingGlasses = nil
    }
  }

  func connect(left: CBPeripheral, right: CBPeripheral) {
    if let name = left.name {
      log("connecting to \(name) (state: \(left.state.rawValue))")
    }
    if let name = right.name {
      log("connecting to \(name) (state: \(right.state.rawValue))")
    }
    leftPeripheral = left
    rightPeripheral = right
    left.delegate = self
    right.delegate = self
    manager.connect(
      left, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    manager.connect(
      right, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    manager.stopScan()
  }

  var waitingGlasses: (String, String)?
  func reconnectKnown(glasses: (String, String)) {
    let peripherals = manager.retrievePeripherals(withIdentifiers: [
      UUID(uuidString: glasses.0)!,
      UUID(uuidString: glasses.1)!,
    ])
    if peripherals.count == 2 {
      connect(left: peripherals[0], right: peripherals[1])
    } else {
      log("reconnectKnown missing peripherals: \(peripherals)")
    }
  }

  var pairing: Pairing?
}

let isBluetoothEnabledAtom = PrimitiveAtom(false)

let isConnectedAtom = PrimitiveAtom(false)

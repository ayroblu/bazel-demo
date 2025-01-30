import CoreBluetooth
import Log
import utils

public struct ConnectionManager {
  let UARTServiceUUID = CBUUID(string: Constants.uartServiceUUIDString)
  let manager = BluetoothManager()
  let centralManager: CBCentralManager
  var connectedPeripherals: [CBPeripheral] = []

  public init() {
    centralManager = CBCentralManager(delegate: manager, queue: nil)
  }

  public mutating func getConnected() -> [CBPeripheral] {
    let peripherals = centralManager.retrieveConnectedPeripherals(withServices: [UARTServiceUUID])
    connectedPeripherals = []
    for peripheral in peripherals {
      guard let name = peripheral.name else { continue }
      guard name.contains("Even") else { continue }
      // guard peripheral.state == .disconnected else { continue }
      log("connecting to \(name) (state: \(peripheral.state.rawValue))")
      connectedPeripherals.append(peripheral)
      peripheral.delegate = manager
      centralManager.connect(
        peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }

    return peripherals
  }

  public func scanConnected() async {
    guard centralManager.state == .poweredOn else {
      log("bluetooth not connected")
      return
    }
    centralManager.scanForPeripherals(withServices: [UARTServiceUUID], options: nil)
    log("scanning")
    try? await Task.sleep(for: .seconds(7))
    centralManager.stopScan()
    log("stop scanning")
  }

  public func disconnect() {
    manager.transmitBoth(getExitData())
    for peripheral in connectedPeripherals {
      centralManager.cancelPeripheralConnection(peripheral)
    }
    log("disconnected")
  }
}

class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  let UARTServiceUUID = CBUUID(string: Constants.uartServiceUUIDString)
  let UARTTXCharacteristicUUID = CBUUID(string: Constants.uartTXCharacteristicUUIDString)
  let UARTRXCharacteristicUUID = CBUUID(string: Constants.uartRXCharacteristicUUIDString)

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
    peripheral.discoverServices([UARTServiceUUID])
  }

  func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    guard let name = peripheral.name else { return }
    log("didFailToConnect \(name)")
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let services = peripheral.services else { return }

    for service in services {
      if service.uuid.isEqual(UARTServiceUUID) {
        peripheral.discoverCharacteristics(nil, for: service)
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
  func transmit(_ data: Data, for peripheral: CBPeripheral, type: CBCharacteristicWriteType) {
    guard let name = peripheral.name else { return }
    guard
      let characteristic = name.contains("_L_")
        ? transmitLeftCharacteristic : transmitRightCharacteristic
    else { return }
    peripheral.writeValue(data, for: characteristic, type: type)
  }

  func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) {
    guard let name = peripheral.name else { return }
    guard let characteristics = service.characteristics else { return }
    guard service.uuid.isEqual(UARTServiceUUID) else { return }
    for characteristic in characteristics {
      switch characteristic.uuid {
      case UARTRXCharacteristicUUID:
        log("rx \(name)")
        peripheral.setNotifyValue(true, for: characteristic)
      case UARTTXCharacteristicUUID:
        log("tx \(name)")
        if name.contains("_L_") {
          transmitLeftCharacteristic = characteristic
          leftPeripheral = peripheral
        } else if name.contains("_R_") {
          transmitRightCharacteristic = characteristic
          rightPeripheral = peripheral
        }
      // peripheral.writeValue(Data([0x4d, 0x01]), for: characteristic, type: .withoutResponse)
      default:
        log("unknown characteristic")
      }
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard let data: Data = characteristic.value else { return }
    let rspCommand = BLE_REC(rawValue: data[0])
    switch rspCommand {
    case .MIC:
      // let hexString = data.map { String(format: "%02hhx", $0) }.joined()
      // let effectiveData = data.subdata(in: 2..<data.count)
      // let pcmConverter = PcmConverter()
      // var pcmData = pcmConverter.decode(effectiveData)

      // let inputData = pcmData as Data
      // SpeechStreamRecognizer.shared.appendPCMData(inputData)

      log("mic received!")
    case .DEVICE:
      // let isLeft = peripheral.identifier.uuidString == "left-uuid"
      let taps = DEVICE_CMD(rawValue: data[1])
      guard let name = peripheral.name else { break }
      switch taps {
      case .SINGLE_TAP:
        log("single tap!", name)
      case .DOUBLE_TAP:
        log("double tap!", name)
      case .TRIPLE_TAP:
        log("triple tap!", name)
      case .LOOK_UP:
        log("look up", name)
        let text = "Looked up!"
        guard let textData = getG1TextData(text: text) else { break }
        transmitBoth(textData)
      case .LOOK_DOWN:
        log("look down", name)
        let text = "Looked down!"
        guard let textData = getG1TextData(text: text) else { break }
        transmitBoth(textData)
      case .DASH_SHOWN:
        log("dash shown", name)
      case .DASH_HIDE:
        log("dash hide", name)
      case .none:
        log("unknown device command: \(data[1])")
      }
    default:
      // log("unknown command: \(data[0])")
      break
    }
  }
}

func getG1TextData(text: String) -> Data? {
  guard let textData = text.data(using: .utf8) else { return nil }
  let cmd = 0x4E
  let seq = 0x00
  let numItems = 0x01
  let item = 0x00
  let newScreen = 0x71  // 0x01 | 0x70, new content | text show
  let newCharPos = [0x00, 0x00]  // Big endian int16
  let pageNum = 0x00
  let pageCount = 0x01

  let controlArr =
    [cmd, seq, numItems, item, newScreen] + newCharPos + [pageNum, pageCount]
  return Data(controlArr.map { UInt8($0) }) + textData
}

func getExitData() -> Data {
  return Data([0x18])
}

enum BLE_REC: UInt8 {
  case MIC = 0xF1
  case DEVICE = 0xF5
}
enum DEVICE_CMD: UInt8 {
  case SINGLE_TAP = 0x01
  case DOUBLE_TAP = 0x00
  case TRIPLE_TAP = 0x04  // or 05??
  case LOOK_UP = 0x02
  case LOOK_DOWN = 0x03
  case DASH_SHOWN = 0x1E
  case DASH_HIDE = 0x1F
}

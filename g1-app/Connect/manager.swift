import CoreBluetooth
import Log
import utils

public struct ConnectionManager {
  public init() {}
  let UARTServiceUUID = CBUUID(string: Constants.uartServiceUUIDString)
  let UARTTXCharacteristicUUID = CBUUID(string: Constants.uartTXCharacteristicUUIDString)
  let UARTRXCharacteristicUUID = CBUUID(string: Constants.uartRXCharacteristicUUIDString)
  let centralManager = CBCentralManager(delegate: BluetoothManager(), queue: nil)

  public func getConnected() -> [CBPeripheral] {
    return centralManager.retrieveConnectedPeripherals(withServices: [UARTServiceUUID])
  }

  public func scanConnected() async {
    guard centralManager.state == .poweredOn else {
      print("bluetooth not connected")
      return
    }
    centralManager.scanForPeripherals(withServices: [UARTServiceUUID], options: nil)
    print("scanning")
    try? await Task.sleep(for: .seconds(7))
    centralManager.stopScan()
    print("stop scanning")
    // centralManager.connect(
    //   leftPeripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
  }
}

class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn:
      print("Bluetooth is powered on.")
    case .poweredOff:
      print("Bluetooth is powered off.")
    default:
      print("Bluetooth state is unknown or unsupported.")
    }
  }

  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    guard let name = peripheral.name else { return }
    print("device", name)
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

      break
    case .DEVICE:
      // let isLeft = peripheral.identifier.uuidString == "left-uuid"
      print("f5!")
      let taps = DEVICE_TAPS(rawValue: data[1])
      switch taps {
      case .SINGLE:
        print("single tap!")
        break
      case .DOUBLE:
        print("double tap!")
        break
      case .TRIPLE:
        print("triple tap!")
        break
      default:
        break
      }
      break
    default:
      break
    }
  }
}

enum BLE_REC: UInt8 {
  case MIC = 0xF1
  case DEVICE = 0xF5
}
enum DEVICE_TAPS: UInt8 {
  case SINGLE = 0x01
  case DOUBLE = 0x00
  case TRIPLE = 0x04  // or 05??
}

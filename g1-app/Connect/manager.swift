import CoreBluetooth
import Log
import Pcm
import Speech
import utils

public struct ConnectionManager {
  let uartServiceCbuuid = CBUUID(string: uartServiceUuid)
  let manager = BluetoothManager()
  let centralManager: CBCentralManager
  var connectedPeripherals: [CBPeripheral] = []

  public init() {
    centralManager = CBCentralManager(delegate: manager, queue: nil)
    manager.manager = self
  }

  public mutating func getConnected() -> [CBPeripheral] {
    let peripherals = centralManager.retrieveConnectedPeripherals(withServices: [uartServiceCbuuid])
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
    centralManager.scanForPeripherals(withServices: [uartServiceCbuuid], options: nil)
    log("scanning")
    try? await Task.sleep(for: .seconds(7))
    centralManager.stopScan()
    log("stop scanning")
  }

  public func disconnect() {
    manager.transmitBoth(G1Cmd.Exit.data())
    for peripheral in connectedPeripherals {
      centralManager.cancelPeripheralConnection(peripheral)
    }
    log("disconnected")
  }

  public func sendText(_ text: String) {
    guard let textData = G1Cmd.Text.data(text: text) else { return }
    manager.transmitBoth(textData)
  }

  func onValue(_ peripheral: CBPeripheral, data: Data) {
    guard let name = peripheral.name else { return }
    let rspCommand = BLE_REC(rawValue: data[0])
    switch rspCommand {
    case .MIC:
      // let hexString = data.map { String(format: "%02hhx", $0) }.joined()
      let effectiveData = data.subdata(in: 2..<data.count)
      let pcmConverter = PcmConverter()
      let pcmData = pcmConverter.decode(effectiveData)

      let inputData = pcmData as Data
      appendPCMData(inputData)

      log("mic received!")
    case .DEVICE:
      // let isLeft = peripheral.identifier.uuidString == "left-uuid"
      let cmd = DEVICE_CMD(rawValue: data[1])
      switch cmd {
      case .SINGLE_TAP:
        log("single tap!", name)
      case .DOUBLE_TAP:
        log("double tap!", name)
      case .TRIPLE_TAP:
        log("triple tap!", name)
      case .LOOK_UP:
        log("look up", name, data.hex)
        // let text = "Looked up!"
        // guard let textData = G1Cmd.Text.data(text: text) else { break }
        // transmitBoth(textData)
        manager.readBoth(Data([BLE_REC.BATTERY.rawValue, 0x02]))
      case .LOOK_DOWN:
        log("look down", name, data.hex)
      // let text = "Looked down!"
      // guard let textData = G1Cmd.Text.data(text: text) else { break }
      // transmitBoth(textData)
      case .DASH_SHOWN:
        log("dash shown", name, data.hex)
      case .DASH_HIDE:
        log("dash hide", name, data.hex)
      case .CASE:
        log("case detected", data.hex)
      case .CASE_CLOSE:
        log("case close", data.hex)
      case .CASE_EXIT:
        log("removed from case", data.hex)
      case .CASE_STATE:
        log("case is open: \(data[2])")
        // 0xf50e01
        break
      case .CASE_BATTERY:
        log("case battery: \(data[2])")
        // 0xf50f46
        break
      case .UNKNOWN_06:
        log("unknown device command: \(name) \(data[1]) \(data.hex)")
        // 0xf506
        break
      case .UNKNOWN_09:
        // 0xf50901
        break
      case .UNKNOWN_0A:
        // 0xf50a64
        break
      case .none:
        log("unknown device command: \(name) \(data[1]) \(data.hex)")
      }
    case .BATTERY:
      switch data[1] {
      case 0x66:
        log("battery: \(name) \(data[2]) \(data.hex)")
      default:
        log("battery: \(name) \(data.hex)")
      }
    case .FIRMWARE_INFO_RES:
      let text = data.ascii() ?? "<>"
      log("firmware: \(name) \(text.trim())")
    case .UNKNOWN_06:
      // On open? proximity?
      // 0x0607000206
      // 0x060700e306
      // 0x061500e401
      // 0x062d00e503010001
      break
    case .UNKNOWN_1E:
      // Similar to 6
      // 0x1e5800e803010001
      // 0x1e2400ea03010001
      // 0x1e1000ec03010001
      // 0x1e06001c01
      break
    case .UNKNOWN_22:
      // Uptime?
      // R: 0x220500e6010301
      //    0x2205003c010301
      //    0x22050044010301
      break
    case .UNKNOWN_29:
      // On open even app
      // 0x29650601
      break
    case .UNKNOWN_2B:
      // very noisy
      // 0x2b690a0b
      // 0x2b690a07
      break
    case .UNKNOWN_37:
      // 0x3737e1bc000001
      break
    default:
      log("unknown command: \(name) \(data[0]) \(data.hex) \(data.ascii() ?? "<>")")
      break
    }
  }

  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  func appendPCMData(_ pcmData: Data) {
    guard let recognitionRequest = recognitionRequest else {
      print("Recognition request is not available")
      return
    }

    let audioFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!
    guard
      let audioBuffer = AVAudioPCMBuffer(
        pcmFormat: audioFormat,
        frameCapacity: AVAudioFrameCount(pcmData.count)
          / audioFormat.streamDescription.pointee.mBytesPerFrame)
    else {
      print("Failed to create audio buffer")
      return
    }
    audioBuffer.frameLength = audioBuffer.frameCapacity

    pcmData.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) in
      if let audioDataPointer = bufferPointer.baseAddress?.assumingMemoryBound(to: Int16.self) {
        let audioBufferPointer = audioBuffer.int16ChannelData?.pointee
        audioBufferPointer?.initialize(
          from: audioDataPointer, count: pcmData.count / MemoryLayout<Int16>.size)
        recognitionRequest.append(audioBuffer)
      } else {
        print("Failed to get pointer to audio data")
      }
    }
  }
}

enum BLE_REC: UInt8 {
  case MIC = 0xF1
  case DEVICE = 0xF5
  case BATTERY = 0x2C
  case FIRMWARE_INFO_REQ = 0x23
  case FIRMWARE_INFO_RES = 0x6E
  case UNKNOWN_06 = 0x06
  case UNKNOWN_1E = 0x1E
  case UNKNOWN_22 = 0x22
  case UNKNOWN_29 = 0x29
  case UNKNOWN_2B = 0x2b
  case UNKNOWN_37 = 0x37
}
enum DEVICE_CMD: UInt8 {
  case SINGLE_TAP = 0x01
  case DOUBLE_TAP = 0x00
  case TRIPLE_TAP = 0x04  // or 05??
  case LOOK_UP = 0x02
  case LOOK_DOWN = 0x03
  case DASH_SHOWN = 0x1E
  case DASH_HIDE = 0x1F
  case CASE_EXIT = 0x07
  case CASE = 0x08
  case CASE_CLOSE = 0x0B
  case CASE_STATE = 0x0E
  case CASE_BATTERY = 0x0F
  case UNKNOWN_06 = 0x06
  case UNKNOWN_09 = 0x09
  case UNKNOWN_0A = 0x0A
}

class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  let uartServiceCbuuid = CBUUID(string: uartServiceUuid)
  let uartTxCharacteristicCbuuid = CBUUID(string: uartTxCharacteristicUuid)
  let uartRxCharacteristicCbuuid = CBUUID(string: uartRxCharacteristicUuid)
  let smpServiceCbuuid = CBUUID(string: smpCharacteristicUuid)
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

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let error = error {
      log("didDiscoverServices error", error)
      return
    }
    guard let services = peripheral.services else { return }

    for service in services {
      if service.uuid == uartServiceCbuuid {
        peripheral.discoverCharacteristics(nil, for: service)
      } else if service.uuid == smpServiceCbuuid && discoverSmb {
        peripheral.discoverCharacteristics(nil, for: service)
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
        // peripheral.writeValue(Data([0x4d, 0x01]), for: characteristic, type: .withoutResponse)
        default:
          log("unknown characteristic")
        }
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
    peripheral.readValue(for: characteristic)
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    if let error = error {
      log("didUpdateValueFor error", error)
      return
    }
    guard let name = peripheral.name else { return }
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
}

extension Data {
  var hex: String {
    return trimEnd().reduce("0x") { $0 + String(format: "%02x", $1) }
  }
  func trimEnd() -> Data {
    let data = self
    var lastNonZero = data.count - 1
    while lastNonZero >= 0 && data[lastNonZero] == 0 {
      lastNonZero -= 1
    }
    if lastNonZero < 0 {
      return Data()
    }
    return data[0...lastNonZero]
  }
  func ascii() -> String? {
    return String(data: self.trimEnd(), encoding: .ascii)
  }
}
extension String {
  func trimEnd() -> String {
    return self.replacingOccurrences(
      of: "\\s+$", with: "", options: .regularExpression)
  }
  func trim() -> String {
    return self.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

import CoreBluetooth
import Log
import Pcm
import Speech

public struct ConnectionManager {
  let uartServiceCbuuid = CBUUID(string: uartServiceUuid)
  let manager = BluetoothManager()
  let centralManager: CBCentralManager
  var connectedPeripherals: [CBPeripheral] = []

  public init() {
    let options = [CBCentralManagerOptionRestoreIdentifierKey: "central-manager-identifier"]
    centralManager = CBCentralManager(delegate: manager, queue: nil, options: options)
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

  public func sendImage() {
    guard let image = image1() else { return }
    Task {
      // manager.readBoth(G1Cmd.Heartbeat.data())
      // try? await Task.sleep(for: .milliseconds(50))
      // log("finished waiting for heartbeat")

      // let dataItems = G1Cmd.Bmp.data(image: image)
      // log("sending \(dataItems.count) items")

      log("start sending bmp")
      for data in G1Cmd.Bmp.data(image: image) {
        manager.transmitBoth(data)
        try? await Task.sleep(for: .milliseconds(8))
      }
      log("finished sending parts")
      manager.readBoth(G1Cmd.Bmp.endData())
      try? await Task.sleep(for: .milliseconds(100))
      manager.readBoth(G1Cmd.Bmp.crcData(inputData: image))
      log("sent crc")
    }
  }

  public func sendNotif() {
    // todo
    // let data = G1Cmd.Notify.data()
  }

  public func listenAudio() {
    // todo
  }

  func onValue(_ peripheral: CBPeripheral, data: Data) {
    guard let name = peripheral.name else { return }
    let rspCommand = BLE_REC(rawValue: data[0])
    switch rspCommand {
    case .MIC:
      let isSuccess = G1Cmd.Mic.respData(data: data).isSuccess
      log("mic action success: \(isSuccess)")
    case .MIC_DATA:
      // let hexString = data.map { String(format: "%02hhx", $0) }.joined()
      let effectiveData = data.subdata(in: 2..<data.count)
      let pcmConverter = PcmConverter()
      let pcmData = pcmConverter.decode(effectiveData)

      let inputData = pcmData as Data
      appendPCMData(inputData)

      log("mic received!")
    case .CRC:
      if G1Cmd.Bmp.crcResp(data: data) {
        log("CRC check failed", data.hex)
      } else {
        log("CRC success")
      }
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

        let text = "Looked up!"
        guard let textData = G1Cmd.Text.data(text: text) else { break }
        manager.transmitBoth(textData)
        manager.readBoth(Data([BLE_REC.BATTERY.rawValue, 0x02]))
      case .LOOK_DOWN:
        log("look down", name, data.hex)
        let text = "Looked down!"
        guard let textData = G1Cmd.Text.data(text: text) else { break }
        manager.transmitBoth(textData)
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
      case .UNKNOWN_11:
        // L only, after Ping
        // 0xf511
        break
      case .UNKNOWN_12:
        // R Only
        // 0xf51206
        // 0xf5120c
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
    case .BmpDone:
      log("bmp done \(name), isSuccess: \(data[1] == 0xC9)")
      break
    case .HEARTBEAT:
      // log("got heartbeat", data.hex)
      break
    case .PING:
      log("ping", data.hex)
      break
    case .TEXT:
      // 0x4ec90001
      break
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
    case .UNKNOWN_3E:
      // Very long, only after ping, only right
      // 0x3ec97bd4477fe46c090051000000b32b0000d60a000007000100e90702027c6500000b000000e907011bbc7f000006000000e907011cf825000003000000e907011dec04000001000000e907011e30cf000005000000e907011f548d000002000000e9070201d89f000006000000e90702023302000095000000e907011b11030000de000000e907011cd100000025000000e907011d0800000002000000e907011e4904000035010000e907011f580100004c000000e9070201a6030000cb
      break
    case .none:
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

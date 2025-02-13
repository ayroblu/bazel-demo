import CoreBluetooth
import Log
import Pcm
import Speech

public class ConnectionManager {
  let uartServiceCbuuid = CBUUID(string: uartServiceUuid)
  let manager = BluetoothManager()
  let centralManager: CBCentralManager
  var mainVm: MainVM?
  var connectedPeripherals: [CBPeripheral] = []

  public init() {
    let options = [CBCentralManagerOptionRestoreIdentifierKey: "central-manager-identifier"]
    centralManager = CBCentralManager(delegate: manager, queue: nil, options: options)
    manager.manager = self
  }

  public func getConnected() -> [CBPeripheral] {
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
    // let allowData = G1Cmd.Notify.allowData(id: Info.id, name: Info.name)
    // for data in allowData {
    //   manager.transmitBoth(data)
    // }
    let data = G1Cmd.Notify.data(
      notifyData: NotifyData(
        title: "New product!",
        subtitle: "hello!", message: "message?"))
    for data in data {
      manager.transmitBoth(data)
    }
  }

  public func dashConfig() {
    let data = G1Cmd.Config.dashData(isShow: true, vertical: 8, distance: 8)
    if let data {
      manager.transmitBoth(data)
    }
    Task {
      try? await Task.sleep(for: .seconds(2))
      if let data = G1Cmd.Config.dashData(isShow: true, vertical: 2, distance: 3) {
        manager.transmitBoth(data)
      }
      try? await Task.sleep(for: .seconds(2))
      let data = G1Cmd.Config.dashData(isShow: false, vertical: 2, distance: 3)
      if let data {
        manager.transmitBoth(data)
      }
    }
  }

  var speechRecognizer: SpeechRecognizer?
  // var micOn = false
  public func listenAudio() {
    if let speech = speechRecognizer {
      speech.stopRecognition()
      speechRecognizer = nil
      manager.readRight(G1Cmd.Mic.data(enable: false))
      manager.transmitBoth(G1Cmd.Exit.data())
      return
    }
    speechRecognizer = SpeechRecognizer { text in
      log("recognized", text)
      guard let textData = G1Cmd.Text.data(text: text) else { return }
      self.manager.transmitBoth(textData)
    }
    manager.readRight(G1Cmd.Mic.data(enable: true))
    speechRecognizer?.startRecognition(locale: Locale(identifier: "en-US"))
    guard let textData = G1Cmd.Text.data(text: "Listening...") else { return }
    manager.transmitBoth(textData)
    log("listening")
  }

  func onValue(_ peripheral: CBPeripheral, data: Data) {
    guard let name = peripheral.name else { return }
    let rspCommand = BLE_REC(rawValue: data[0])
    switch rspCommand {
    case .ERROR:
      let code = data[1]
      let msg = data.subdata(in: 2..<data.count).ascii() ?? "<>"
      log("00: \(name) \(code.hex) \(msg)")
      break
    case .AutoBrightness:
      // 0x01c9
      break
    case .SilentMode:
      // 0x03c9
      break
    case .AddNotif:
      // 0x04ca
      log("Add notif resp: \(name) \(data.hex)")
      break
    case .MIC:
      let resp = G1Cmd.Mic.respData(data: data)
      log("mic action success: \(resp.isSuccess), enabled: \(resp.enable)")
    case .MIC_DATA:
      let effectiveData = data.subdata(in: 2..<data.count)
      let pcmConverter = PcmConverter()
      let pcmData = pcmConverter.decode(effectiveData)

      let inputData = pcmData as Data
      speechRecognizer?.appendPcmData(inputData)
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
      case .TRIPLE_TAP_SILENT:
        log("silent mode on", name)
      case .TRIPLE_TAP_NORMAL:
        log("not silent mode", name)
      case .LOOK_UP:
        log("look up", name, data.hex)

      // let text = "Looked up!"
      // guard let textData = G1Cmd.Text.data(text: text) else { break }
      // manager.transmitBoth(textData)
      case .LOOK_DOWN:
        log("look down", name, data.hex)
      // let text = "Looked down!"
      // guard let textData = G1Cmd.Text.data(text: text) else { break }
      // manager.transmitBoth(textData)
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
        switch data[1] {
        case 0x00:
          break
        default:
          log("unknown device command: \(name) \(data[1]) \(data.hex)")
          break
        }
      }
    case .BATTERY:
      switch data[1] {
      case 0x66:
        // (Left)
        // 0x2c66 4b 00 d3 94 20 000000 01 05
        // 0x2c66 4b 00 d3 83 20 000000 01 05
        // 0x2c66 4b 00 d4 88 20 000000 01 05
        // (Right)
        // 0x2c66 4d 4c d6 83 1e 01 05 00 01 05
        // 0x2c66 4d 4c d6 83 1e 01 05 00 01 05
        // 0x2c66 4d 4c d6 81 1e 01 05 00 01 05
        log("battery: \(name) \(data[2]) \(data.hex)")
      default:
        log("battery: \(name) \(data.hex)")
      }
    case .FIRMWARE_INFO_RES:
      // let text = data.ascii() ?? "<>"
      // log("firmware: \(name) \(text.trim())")
      break
    case .HeadTilt:
      // Right only
      // 0x0bc9
      break
    case .DashConfig:
      // dash control
      // 0x2606000102c9
      log("dash control \(data.hex)")
      break
    case .BmpDone:
      log("bmp done \(name), isSuccess: \(data[1] == 0xC9)")
      break
    case .NOTIF:
      let isSuccess = data[1] == 0xC9 || data[1] == 0xCB
      log("notif \(name), isSuccess: \(isSuccess), \(data.hex)")
    case .HEARTBEAT:
      // log("got heartbeat", data.hex)
      break
    case .PING:
      log("ping", data.hex)
      break
    case .TEXT:
      // 0x4ec90001
      break
    case .Exit:
      // ack exit
      // 0x18c9
      break
    case .NOTIF_SETTING:
      // New App notif discovered:
      // {"whitelist_app_add": {"app_identifier":  "com.ayroblu.g1-app","display_name": "G1 Bazel App"}}
      let parts = data[1]
      let seq = data[2]
      let rest = data.subdata(in: 3..<data.count)
      if seq == 0 {
        f6Data[peripheral] = [rest]
      } else {
        if var list = f6Data[peripheral], list.count == seq {
          list.append(rest)
          f6Data[peripheral] = list
        }
      }
      if let list = f6Data[peripheral], seq == parts - 1 {
        let data = Data(list.joined())
        log("0xF6: \(name) [\(data.count)]", data.ascii() ?? "<>")
      }
      break
    case .none:
      switch data[0] {
      case 0x06:
        // On open? proximity? Config update?
        // 6, 22 1E are all triggered on note update
        // 0x0607000206
        // 0x060700e306
        // 0x061500e401
        // 0x062d00e503010001
        // log("0x06: \(name) \(data.hex)")
        break
      case 0x08:
        // on pairing
        // 0x0806000004
        break
      case 0x14:
        // After opening notifications
        // 0x14c9
        break
      case 0x1E:
        // response to note update I think
        log("0x1E: \(name) \(data.hex)")
        // Similar to 6
        // 0x1e5800e803010001
        // 0x1e2400ea03010001
        // 0x1e1000ec03010001
        // 0x1e06001c01
        break
      case 0x22:
        // log("0x22: \(name) \(data.hex)")
        // Uptime?
        // R: 0x220500e6010301
        //    0x2205003c010301
        //    0x22050044010301
        break
      case 0x29:
        // On open even app
        // 0x29650601
        break
      case 0x2A:
        // After opening settings
        // 0x2a6801
        break
      case 0x2B:
        // very noisy
        // 0x2b690a0b
        // 0x2b690a07
        break
      case 0x32:
        // Right only after opening settings
        // 0x326d1501
        break
      case 0x3A:
        // After opening settings
        // 0x3ac901
        break
      case 0x37:
        // time since boot in seconds?
        // 0x3737e1bc000001
        break
      case 0x39:
        // on dash control
        // 0x390500cf01
        break
      case 0x3B:
        // on load, right only
        // 0x3bc90303
        // 0x3bc90103 (set display position?)
        break
      case 0x3E:
        // Very long, only after ping, only right
        // Fetch buried point data, which is essentially user usage tracking: https://www.php.cn/faq/446290.html
        // 0x3ec97bd4477fe46c090051000000b32b0000d60a000007000100e90702027c6500000b000000e907011bbc7f000006000000e907011cf825000003000000e907011dec04000001000000e907011e30cf000005000000e907011f548d000002000000e9070201d89f000006000000e90702023302000095000000e907011b11030000de000000e907011cd100000025000000e907011d0800000002000000e907011e4904000035010000e907011f580100004c000000e9070201a6030000cb
        break
      case 0x3F:
        // On pairing
        // 0x3f05c9
        break
      case 0x4F:
        // On pairing
        // 0x4fc901
        break
      case 0x50:
        // right only
        // 0x500600000101
        break
      default:
        log(
          "unknown command: \(name) \(data[0]) \(data.hex) \(data.subdata(in: 1..<data.count).ascii() ?? "<>")"
        )
        break
      }
    }
  }
  var f6Data: [CBPeripheral: [Data]] = [:]

  func onConnect() {
    manager.readBoth(Data([BLE_REC.BATTERY.rawValue, 0x02]))
  }
}

import CoreBluetooth
import Log
import Pcm
import Speech
import SwiftData

public class ConnectionManager {
  let uartServiceCbuuid = CBUUID(string: uartServiceUuid)
  let manager = BluetoothManager()
  let centralManager: CBCentralManager
  var mainVm: MainVM?
  var connectedPeripherals: [CBPeripheral] {
    return [manager.leftPeripheral, manager.rightPeripheral].compactMap { $0 }
  }

  public init() {
    let options = [CBCentralManagerOptionRestoreIdentifierKey: "central-manager-identifier"]
    centralManager = CBCentralManager(delegate: manager, queue: nil, options: options)
    manager.manager = self
  }

  var pairing: Pairing?

  func syncUnknown(modelContext: ModelContext) {
    let pairing = Pairing(modelContext: modelContext, connect: connect)
    self.pairing = pairing

    startScan()
  }

  private func startScan() {
    guard let pairing else { return }
    let peripherals = centralManager.retrieveConnectedPeripherals(withServices: [
      uartServiceCbuuid
    ])
    for peripheral in peripherals {
      if pairing.onPeripheral(peripheral: peripheral) {
        return
      }
    }
    log("No paired peripherals found")
    // centralManager.scanForPeripherals(withServices: [uartServiceCbuuid])
    centralManager.scanForPeripherals(withServices: nil)
  }

  func stopPairing() {
    if pairing != nil {
      pairing = nil
      centralManager.stopScan()
    }
  }

  var leftPeripheral: CBPeripheral?
  var rightPeripheral: CBPeripheral?
  func connect(left: CBPeripheral, right: CBPeripheral) {
    if let name = left.name {
      log("connecting to \(name) (state: \(left.state.rawValue))")
    }
    if let name = right.name {
      log("connecting to \(name) (state: \(right.state.rawValue))")
    }
    leftPeripheral = left
    rightPeripheral = right
    left.delegate = manager
    right.delegate = manager
    centralManager.connect(
      left, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    centralManager.connect(
      right, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    centralManager.stopScan()
  }

  public func getConnected() -> [CBPeripheral] {
    let peripherals = centralManager.retrieveConnectedPeripherals(withServices: [uartServiceCbuuid])
    for peripheral in peripherals {
      guard let name = peripheral.name else { continue }
      guard name.contains("Even") else { continue }
      // guard peripheral.state == .disconnected else { continue }
      log("connecting to \(name) (state: \(peripheral.state.rawValue))")
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

  public func toggleSilentMode() {
    if let mainVm {
      let data = G1Cmd.Config.silentModeData(enabled: !mainVm.silentMode)
      manager.transmitBoth(data)
      mainVm.silentMode = !mainVm.silentMode
    }
  }

  public func sendBrightness() {
    if let mainVm {
      let data = G1Cmd.Config.brightnessData(
        brightness: mainVm.brightness, auto: mainVm.autoBrightness)
      manager.readRight(data)
    }
  }

  public func dashPosition() {
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

  public func dashNotes() {
    let testNote = G1Cmd.Config.Note(
      title: "Just a test",
      text: "This is just for illustration\nMore todo"
    )
    let testNote2 = G1Cmd.Config.Note(
      title: "Example second",
      text: "..."
    )
    let data = G1Cmd.Config.notesData(notes: [testNote, testNote2])
    for data in data {
      manager.transmitBoth(data)
    }
  }

  public func dashCalendar() {
    let event = G1Cmd.Config.Event(
      name: "App time",
      time: "13:00-14:00",
      location: "Cloud"
    )
    let data = G1Cmd.Config.calendarData(event: event)
    manager.transmitBoth(data)
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
    let isLeft = peripheral == manager.leftPeripheral
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
      logFailure(code: data[1], type: "autobrightness", name: name, data: data)
    case .SilentMode:
      // 0x03c9
      logFailure(code: data[1], type: "silent mode", name: name, data: data)
    case .AddNotif:
      // 0x04ca
      logFailure(code: data[1], type: "add notif", name: name, data: data)
    case .DashMode:
      switch data[1] {
      case 0x07:
        // mode: (full dual minimal)
        // 0x0607003b06
        break
      case 0x15:
        // dash time and weather
        // 0x0615003801
        break
      default:
        // Probably calendar?
        // log("unknown dash cmd: \(name) \(data.hex)")
        break
      }
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
    case .GlassesState:
      // 0x2b690a0b
      // 0x2b690a07
      // Right is sometimes wrong
      if !isLeft {
        break
      }
      var isCaseOpen = mainVm?.isCaseOpen
      switch data[3] {
      case 0x06:
        // Wearing
        isCaseOpen = nil
      case 0x07:
        isCaseOpen = nil
      case 0x08:
        isCaseOpen = true
      case 0x0B:
        isCaseOpen = false
      default:
        log("UNKNOWN 0x2B: \(name) \(data.hex)")
      }
      if let silentMode = data[2] == 0x0C ? true : data[2] == 0x0A ? false : nil {
        mainVm?.silentMode = silentMode
      } else {
        log("unknown mode state \(name) \(data.hex)")
      }
      if isCaseOpen != mainVm?.isCaseOpen {
        mainVm?.isCaseOpen = isCaseOpen
        log("isCaseOpen: \(name) \(String(describing: isCaseOpen)) \(data.hex)")
      }
    case .Uptime:
      // time since boot in seconds?
      // 0x3737e1bc000001
      break
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
      case .CASE_OPEN:
        log("case open", data.hex)
        mainVm?.isCaseOpen = true
      case .CASE_CLOSE:
        log("case close", data.hex)
        mainVm?.isCaseOpen = false
      // case .CASE_EXIT:
      //   log("removed from case", data.hex)
      //   mainVm?.isCaseOpen = nil
      case .CASE_STATE:
        log("case is open: \(data[2])")
        // mainVm?.isCaseOpen = data[2] == 1
        // 0xf50e01
        break
      case .CASE_BATTERY:
        log("case battery: \(data[2])")
        mainVm?.caseBattery = Int(data[2])
        // 0xf50f46
        break
      case .WEAR_ON:
        log("wear on: \(name) \(data.hex)")
        // 0xf506
        break
      case .WEAR_OFF:
        log("wear off: \(name) \(data.hex)")
        // wear off is also not in case
        mainVm?.isCaseOpen = nil
        // 0xf507
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

        // log(
        //   "battery: \(name) \(data[2]), info: \(data.subdata(in: 4..<7).hexSpace)| \(data.hex)"
        // )
        if isLeft {
          mainVm?.leftBattery = Int(data[2])
        } else {
          mainVm?.rightBattery = Int(data[2])
        }
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
      logFailure(code: data[1], type: "head tilt", name: name, data: data)
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
        // log("0x1E: \(name) \(data.hex)")
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
        // On open even app from [0x29] send
        let brightness = data[2]
        let isAutoBrightness = data[3] == 0x01
        // Max brightness: 42
        mainVm?.brightness = brightness
        mainVm?.autoBrightness = isAutoBrightness
      // log("auto brightness \(name) \(brightness) \(isAutoBrightness) | \(data.hex)")
      case 0x2A:
        // After opening settings
        // 0x2a6801
        break
      case 0x32:
        // Right only after opening settings
        // 0x326d1501
        break
      case 0x3A:
        // After opening settings
        // 0x3ac901
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
        // 0x3ec97bd44...
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
    if let pairing, let left = manager.leftPeripheral, let right = manager.rightPeripheral {
      log("onConnect - inserting GlassesModel")
      pairing.modelContext.insert(
        GlassesModel(left: left.identifier.uuidString, right: right.identifier.uuidString))
      self.pairing = nil
    }
    deviceInfo()
    mainVm?.isConnected = true
  }
  func deviceInfo() {
    manager.readLeft(Data([SendCmd.GlassesState.rawValue]))
    manager.readBoth(Data([BLE_REC.BATTERY.rawValue, 0x02]))
    manager.readRight(Data([SendCmd.BrightnessState.rawValue]))
  }
}
func logFailure(code: UInt8, type: String, name: String, data: Data) {
  switch RespCode(rawValue: code) {
  case .Success:
    break
  case .Continue:
    break
  case .Failure, .none:
    log("failure: \(type) \(name) \(data.hex)")
  }
}
enum RespCode: UInt8 {
  case Success = 0xC9
  case Continue = 0xCA
  case Failure = 0xCB
}

struct LeftRight {
  let left: CBPeripheral?
  let right: CBPeripheral?
}
class Pairing {
  var paired: [String: LeftRight] = [:]
  let modelContext: ModelContext
  let connect: (CBPeripheral, CBPeripheral) -> Void

  init(
    modelContext: ModelContext, connect: @escaping (CBPeripheral, CBPeripheral) -> Void
  ) {
    self.modelContext = modelContext
    self.connect = connect
  }

  func onPeripheral(peripheral: CBPeripheral) -> Bool {
    guard let name = peripheral.name else { return false }
    guard name.contains("Even G1") else { return false }

    let components = name.components(separatedBy: "_")
    guard components.count > 1, let channelNumber = components[safe: 1] else { return false }
    if let lr = paired[channelNumber] {
      if let right = lr.right, name.contains("_L_") {
        connect(peripheral, right)
        return true
      }
      if let left = lr.left, name.contains("_R_") {
        connect(left, peripheral)
        return true
      }
    } else {
      if name.contains("_L_") {
        paired[channelNumber] = LeftRight(left: peripheral, right: nil)
      } else if name.contains("_R_") {
        paired[channelNumber] = LeftRight(left: nil, right: peripheral)
      }
    }
    return false
  }
}

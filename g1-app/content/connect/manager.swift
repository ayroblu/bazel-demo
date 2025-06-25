import EventKit
import Log
import MapKit
import Pcm
import Speech
import SwiftData
import g1protocol
import jotai

public class ConnectionManager {
  // let uartServiceCbuuid = CBUUID(string: uartServiceUuid)
  let eventStore = EKEventStore()
  var mainVm: MainVM?
  // var connectedPeripherals: [CBPeripheral] {
  //   return [manager.leftPeripheral, manager.rightPeripheral].compactMap { $0 }
  // }

  public init() {
    requestCalendarAccessIfNeeded()
    requestReminderAccessIfNeeded()
    let _ = bluetoothManager.addOnConnectListener(onConnect)
  }

  var glasses: GlassesModel?

  // public func getConnected() -> [CBPeripheral] {
  //   let peripherals = centralManager.retrieveConnectedPeripherals(withServices: [uartServiceCbuuid])
  //   for peripheral in peripherals {
  //     guard let name = peripheral.name else { continue }
  //     guard name.contains("Even") else { continue }
  //     // guard peripheral.state == .disconnected else { continue }
  //     log("connecting to \(name) (state: \(peripheral.state.rawValue))")
  //     peripheral.delegate = manager
  //     centralManager.connect(
  //       peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
  //   }

  //   return peripherals
  // }

  var currentTask: Task<(), Never>?

  public func sendText(_ text: String) {
    guard let textData = Device.Text.data(text: text) else { return }
    bluetoothManager.transmitBoth(textData)
  }

  public func sendWearMessage() {
    Task {
      deviceInfo()
      try? await Task.sleep(for: .milliseconds(100))
      guard let battery = store.get(atom: batteryAtom) else { return }
      sendText("                    Glasses initialized [\(battery)%]")
      try? await Task.sleep(for: .seconds(2))

      bluetoothManager.transmitBoth(Device.exitData())
    }
  }

  public func sendImage() {
    guard let image = image1() else { return }
    Task {
      // bluetoothManager.readBoth(Device.Heartbeat.data())
      // try? await Task.sleep(for: .milliseconds(50))
      // log("finished waiting for heartbeat")

      // let dataItems = Device.Bmp.data(image: image)
      // log("sending \(dataItems.count) items")

      log("start sending bmp")
      for data in Device.Bmp.data(image: image) {
        bluetoothManager.transmitBoth(data)
        try? await Task.sleep(for: .milliseconds(8))
      }
      log("finished sending parts")
      bluetoothManager.readBoth(Device.Bmp.endData())
      try? await Task.sleep(for: .milliseconds(100))
      bluetoothManager.readBoth(Device.Bmp.crcData(inputData: image))
      log("sent crc")
    }
  }

  public func sendAllowNotifs() {
    Task { @MainActor in
      let notifConfig = try getNotifConfig()
      let allowData = Device.Notify.allowData(notifConfig: notifConfig)
      for data in allowData {
        bluetoothManager.readLeft(data)
      }
    }
  }

  public func sendNotif() {
    let data = Device.Notify.data(
      notifyData: Device.Notify.NotifyData(
        title: "New product!",
        subtitle: "hello!", message: "message?"))
    for data in data {
      bluetoothManager.transmitBoth(data)
    }
  }

  public func sendNotifConfig() {
    bluetoothManager.transmitBoth(
      Device.Notify.configData(
        directPush: notifDirectPush, durationS: notifDurationSeconds))
  }

  public func toggleSilentMode() {
    store.set(atom: silentModeAtom) { silentMode in !silentMode }
    let silentMode = store.get(atom: silentModeAtom)
    let data = Config.silentModeData(enabled: silentMode)
    bluetoothManager.transmitBoth(data)
  }

  let store = JotaiStore.shared
  public func sendBrightness() {
    let brightness = store.get(atom: brightnessAtom)
    let autoBrightness = store.get(atom: autoBrightnessAtom)
    let data = Config.brightnessData(brightness: brightness, auto: autoBrightness)
    bluetoothManager.readRight(data)
  }

  public func headsUpAngle(angle: UInt8) {
    guard let data = Config.headTiltData(angle: angle) else { return }
    bluetoothManager.transmitBoth(data)
  }

  func headsUpConfig(_ config: Config.HeadsUpConfig) {
    let data = Config.headsUpConfig(config)
    bluetoothManager.transmitRight(data)
  }

  public func dashPosition(isShow: Bool, vertical: UInt8, distance: UInt8) {
    guard let data = Config.dashData(isShow: isShow, vertical: vertical, distance: distance)
    else { return }
    bluetoothManager.transmitBoth(data)
  }

  func dashNotes(notes: [Config.Note]) {
    let data = Config.notesData(notes: notes)
    for data in data {
      bluetoothManager.transmitBoth(data)
    }
  }

  var speechRecognizer: SpeechRecognizer?
  // var micOn = false
  public func listenAudio() {
    if let speech = speechRecognizer {
      speech.stopRecognition()
      speechRecognizer = nil
      bluetoothManager.readRight(Device.Mic.data(enable: false))
      bluetoothManager.transmitBoth(Device.exitData())
      return
    }
    speechRecognizer = SpeechRecognizer { text in
      log("recognized", text)
      guard let textData = Device.Text.data(text: text) else { return }
      bluetoothManager.transmitBoth(textData)
    }
    bluetoothManager.readRight(Device.Mic.data(enable: true))
    speechRecognizer?.startRecognition(locale: Locale(identifier: "en-US"))
    guard let textData = Device.Text.data(text: "Listening...") else { return }
    bluetoothManager.transmitBoth(textData)
    log("listening")
  }

  func onConnect(left: String, right: String) {
    log("onConnect")
    Task { @MainActor in
      if glasses == nil {
        log("onConnect - inserting GlassesModel")
        if let glassesModel = try? insertOrUpdateGlassesModel(left: left, right: right) {
          glasses = glassesModel
        }
      }
      let _ = infoListeners()
      checkWeather()
      deviceInfo()
      syncReminders()
      sendAllowNotifs()
      bluetoothManager.startTimer()
    }
  }

  func deviceInfo() {
    log("reading deviceInfo")
    bluetoothManager.readLeft(Info.glassesStateData())
    bluetoothManager.readLeft(Info.batteryData())
    bluetoothManager.readRight(Info.brightnessStateData())
    bluetoothManager.readRight(Info.dashPositionData())
    bluetoothManager.readRight(Info.headsUpData())
    bluetoothManager.readRight(Config.getHeadsUpConfig())
    guard let glasses else { return }
    if glasses.leftLensSerialNumber == nil || glasses.rightLensSerialNumber == nil {
      bluetoothManager.readBoth(Info.lensSerialNumberData())
    }
    if glasses.deviceSerialNumber == nil {
      bluetoothManager.readLeft(Info.deviceSerialNumberData())
    }
  }
}
var disposeInfoListeners: (() -> Void)?
@MainActor
func infoListeners() {
  guard disposeInfoListeners == nil else { return }
  let disposeLensSerialNumber = addListener(key: Cmd.LensSerialNumber) {
    (peripheral, data, side, store) in
    guard let glasses = try? fetchGlassesModel() else { return }
    let serialNumber = data.subdata(in: 1..<data.count).ascii()
    if side == .left {
      glasses.leftLensSerialNumber = serialNumber
    } else {
      glasses.rightLensSerialNumber = serialNumber
    }
  }
  let disposeDeviceSerialNumber = addListener(key: Cmd.DeviceSerialNumber) {
    (peripheral, data, side, store) in
    let serialNumber = data.subdata(in: 1..<data.count).ascii()
    guard let glasses = try? fetchGlassesModel() else { return }
    glasses.deviceSerialNumber = serialNumber
  }

  disposeInfoListeners = {
    disposeLensSerialNumber()
    disposeDeviceSerialNumber()
  }
}

var disposeDeviceListeners: (() -> Void)?
extension ConnectionManager {
  @MainActor
  func deviceListeners() {
    guard disposeDeviceListeners == nil else { return }

    let disposeMicData = addListener(key: Cmd.MicData) { (peripheral, data, side, store) in
      let effectiveData = data.subdata(in: 2..<data.count)
      let pcmConverter = PcmConverter()
      let pcmData = pcmConverter.decode(effectiveData)

      let inputData = pcmData as Data
      manager.speechRecognizer?.appendPcmData(inputData)
    }

    let disposeDevice = addListener(key: Cmd.Device) { (peripheral, data, side, store) in
      let cmd = DeviceCmd(rawValue: data[1])
      switch cmd {
      case .DashShown:
        self.syncEvents()
        self.checkWeather()
      case .WearOn:
        self.sendWearMessage()
      default:
        break
      }
    }

    disposeDeviceListeners = {
      disposeMicData()
      disposeDevice()
    }
  }
}

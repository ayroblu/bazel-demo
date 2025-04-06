import CoreBluetooth
import EventKit
import Log
import MapKit
import Pcm
import Speech
import SwiftData

public class ConnectionManager {
  let uartServiceCbuuid = CBUUID(string: uartServiceUuid)
  let manager = BluetoothManager()
  let eventStore = EKEventStore()
  // let calendar = CalendarManager()
  let centralManager: CBCentralManager
  var mainVm: MainVM?
  var connectedPeripherals: [CBPeripheral] {
    return [manager.leftPeripheral, manager.rightPeripheral].compactMap { $0 }
  }

  public init() {
    let options = [CBCentralManagerOptionRestoreIdentifierKey: "central-manager-identifier"]
    centralManager = CBCentralManager(delegate: manager, queue: nil, options: options)
    manager.manager = self
    requestCalendarAccessIfNeeded()
    requestReminderAccessIfNeeded()
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

  var glasses: GlassesModel?
  func syncKnown(glasses: GlassesModel) {
    if let left = manager.leftPeripheral, let right = manager.rightPeripheral,
      left.state == .connected && right.state == .connected
    {
      return
    }
    if centralManager.state == .poweredOn {
      reconnectKnown(glasses: glasses)
    } else {
      self.glasses = glasses
    }
  }

  func reconnectKnown(glasses: GlassesModel) {
    let peripherals = centralManager.retrievePeripherals(withIdentifiers: [
      UUID(uuidString: glasses.left)!,
      UUID(uuidString: glasses.right)!,
    ])
    if peripherals.count == 2 {
      connect(left: peripherals[0], right: peripherals[1])
    } else {
      log("reconnectKnown missing peripherals: \(peripherals)")
    }
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

  var currentTask: Task<(), Never>?

  public func sendText(_ text: String) {
    guard let textData = G1Cmd.Text.data(text: text) else { return }
    manager.transmitBoth(textData)
  }

  public func sendWearMessage() {
    Task {
      deviceInfo()
      try? await Task.sleep(for: .milliseconds(100))
      guard let battery = mainVm?.battery else { return }
      sendText("                    Glasses initialized [\(battery)%]")
      try? await Task.sleep(for: .seconds(2))

      let data = G1Cmd.Exit.data()
      manager.transmitBoth(data)
    }
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

  public func headsUpAngle(angle: UInt8) {
    guard let data = G1Cmd.Config.headTiltData(angle: angle) else { return }
    manager.transmitBoth(data)
  }

  public func dashPosition(isShow: Bool, vertical: UInt8, distance: UInt8) {
    guard let data = G1Cmd.Config.dashData(isShow: isShow, vertical: vertical, distance: distance)
    else { return }
    manager.transmitBoth(data)
  }

  func dashNotes(notes: [G1Cmd.Config.Note]) {
    let data = G1Cmd.Config.notesData(notes: notes)
    for data in data {
      manager.transmitBoth(data)
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

  func onConnect() {
    if let pairing, let left = manager.leftPeripheral, let right = manager.rightPeripheral {
      log("onConnect - inserting GlassesModel")
      pairing.modelContext.insert(
        GlassesModel(left: left.identifier.uuidString, right: right.identifier.uuidString))
      self.pairing = nil
    }

    deviceInfo()
    syncReminders()

    mainVm?.isConnected = true
  }

  func deviceInfo() {
    manager.readLeft(Data([SendCmd.GlassesState.rawValue]))
    manager.readBoth(Data([BLE_REC.BATTERY.rawValue, 0x02]))
    manager.readRight(Data([SendCmd.BrightnessState.rawValue]))
    manager.readRight(Data([SendCmd.DashPosition.rawValue]))
    manager.readRight(Data([SendCmd.HeadsUp.rawValue]))
  }
}

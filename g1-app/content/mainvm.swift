import Log
import MapKit
import SwiftUI
import utils

class MainVM: ObservableObject {
  @Published var devices: [String] = []
  @Published private var _text: String = "Hi there!"
  @Published var selection: TextSelection? = nil
  private var previous: String = ""
  @Published var isConnected: Bool = false
  @Published var glassesState: GlassesState = GlassesState.Off
  @Published var leftBattery: Int?
  @Published var rightBattery: Int?
  @Published var silentMode: Bool = false
  @Published var brightness: UInt8 = 6
  @Published var autoBrightness: Bool = true
  @Published var isBluetoothEnabled: Bool = false
  @Published var headsUpAngle: UInt8 = 30
  @Published var dashVertical: UInt8 = 3
  @Published var dashDistance: UInt8 = 2
  var battery: Int? {
    if let leftBattery, let rightBattery {
      return min(leftBattery, rightBattery)
    }
    if let leftBattery {
      return leftBattery
    }
    if let rightBattery {
      return rightBattery
    }
    return nil
  }
  @Published var caseBattery: Int?
  var text: String {
    get {
      if let selection {
        let toSend = textWithCursor(text: _text, selection: selection)
        if toSend != previous {
          previous = toSend
          sendText(toSend)
        }
      }
      return _text
    }
    set {
      _text = newValue
    }
  }

  var connectionManager = ConnectionManager()
  init() {
    connectionManager.mainVm = self
  }

  func connect() {
    Task {
      await connectionManager.scanConnected()
    }
  }

  func list() {
    let connected = connectionManager.getConnected()
    let newDevices: [String] = connected.compactMap { device in
      guard let name = device.name else { return nil }
      return name
    }
    devices = newDevices
  }
  func sendImage() {
    connectionManager.sendImage()
  }

  func sendNotif() {
    connectionManager.sendNotif()
  }

  func disconnect() {
    devices = []
    connectionManager.disconnect()
  }

  private func sendText(_ text: String) {
    connectionManager.sendText(text)
  }
}

func textWithCursor(text: String, selection: TextSelection) -> String {
  var toSend = text
  switch selection.indices {
  case .selection(let range):
    if toSend.indices.contains(range.lowerBound) {
      toSend.insert("l", at: range.lowerBound)
    } else {
      toSend.append("l")
    }
    break
  default:
    break
  }
  return toSend
}

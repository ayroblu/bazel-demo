import Connect
import Log
import SwiftUI
import utils

class MainVM: ObservableObject {
  @Published var devices: [String] = []
  @Published private var _text: String = "Hi there!"
  @Published var selection: TextSelection? = nil
  private var previous: String = ""
  var text: String {
    get {
      if let selection = selection {
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

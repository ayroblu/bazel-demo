import Log
import MapKit
import SwiftUI
import utils

let manager = ConnectionManager()

class MainVM: ObservableObject {
  @Published private var _text: String = "Hi there!"
  @Published var selection: TextSelection? = nil
  private var previous: String = ""
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
  @Published var searchResults: [LocSearchResult] = []

  var locationSub: (() -> Void)?
  var locationSubInner: (() -> Void)?

  var connectionManager = manager
  init() {
    connectionManager.mainVm = self
  }

  // func connect() {
  //   Task {
  //     await connectionManager.scanConnected()
  //   }
  // }

  // func list() {
  //   let connected = connectionManager.getConnected()
  //   let newDevices: [String] = connected.compactMap { device in
  //     guard let name = device.name else { return nil }
  //     return name
  //   }
  //   devices = newDevices
  // }
  func sendImage() {
    connectionManager.sendImage()
  }

  func sendNotif() {
    connectionManager.sendNotif()
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

enum GlassesAppState {
  case Text
  case Navigation
  case Dash
  case Bmp
}

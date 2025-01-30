import Connect
import SwiftUI
import utils

class MainVM: ObservableObject {
  @Published var devices: [String] = []

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
    connectionManager.disconnect()
  }
}

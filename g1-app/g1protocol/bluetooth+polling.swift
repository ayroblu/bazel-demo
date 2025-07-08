import CoreBluetooth
import Log

private var timer: Timer?
extension BluetoothManager {
  public func startTimer() {
    timer?.invalidate()
    log("BluetoothManager: start timer")
    timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { timer in
      heartbeat()
    }
  }

  private func heartbeat() {
    // log("BluetoothManager: poll connection fired!")
    guard let left = manager.leftPeripheral, let right = manager.rightPeripheral
    else {
      log("BluetoothManager poll: peripheral not found")
      return
    }
    for p in [left, right] {
      if p.state == .disconnected {
        manager.manager.connect(
          p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        log("BluetoothManager poll: connecting to", p.name ?? "<unknown>")
      }
    }
    transmitBoth(Device.Heartbeat.data())
  }
}

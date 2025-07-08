import CoreBluetooth
import Log

private var timer: Timer?
extension BluetoothManager {
  public func startTimer() {
    timer?.invalidate()
    log("BluetoothManager: start timer")
    timer = Timer.scheduledTimer(withTimeInterval: 28.0, repeats: true) { timer in
      log("BluetoothManager: poll connection fired!")
      guard let left = manager.leftPeripheral, let right = manager.rightPeripheral
      else {
        log("BluetoothManager: peripheral not found")
        return
      }
      for p in [left, right] {
        if p.state != .connected {
          manager.manager.connect(
            p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
          log("BluetoothManager: connecting to", p.name ?? "<unknown>")
        }
      }
      transmitBoth(Device.Heartbeat.data())
    }
  }
}

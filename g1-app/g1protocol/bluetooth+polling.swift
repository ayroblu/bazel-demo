import CoreBluetooth
import Log

var timer: Timer?
extension BluetoothManager {
  public func startTimer() {
    timer?.invalidate()
    log("start timer")
    timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { timer in
      log("Poll connection fired!")
      guard let left = manager.leftPeripheral, let right = manager.rightPeripheral
      else {
        log("peripheral not found")
        return
      }
      for p in [left, right] {
        if p.state != .connected {
          manager.manager.connect(
            p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
          log("Connecting to", p.name ?? "<unknown>")
        }
      }
      transmitBoth(Device.Heartbeat.data())
    }
  }
}

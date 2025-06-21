import CoreBluetooth
import Foundation
import jotai

struct G1Info {
  static func batteryData() -> Data {
    return Data([Cmd.Battery.rawValue, 0x02])
  }
  static func glassesStateData() -> Data {
    return Data([Cmd.GlassesState.rawValue])
  }
  static func firmwareData() -> Data {
    return Data([Cmd.FirmwareInfo.rawValue, 0x74])
  }
  static func restartData() -> Data {
    return Data([Cmd.FirmwareInfo.rawValue, 0x72])
  }
  static func lensSerialNumberData() -> Data {
    return Data([Cmd.LensSerialNumber.rawValue])
  }
  static func deviceSerialNumberData() -> Data {
    return Data([Cmd.DeviceSerialNumber.rawValue])
  }
}
var infoListeners: [Cmd: Listener] = [
  Cmd.Battery: { (peripheral, data, side, store) in
    print("Battery")
  }
]

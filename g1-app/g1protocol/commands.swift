import CoreBluetooth
import Foundation
import Log
import jotai

public enum Cmd: UInt8, CaseIterable {
  case Error = 0x00
  case Brightness = 0x01
  case SilentMode = 0x03
  case AddNotif = 0x04
  case DashMode = 0x06
  case HeadsUpConfig = 0x08
  case Navigate = 0x0A
  case HeadTilt = 0x0B
  case Mic = 0x0E
  case Bmp = 0x15
  case Crc = 0x16
  case Exit = 0x18
  case Notes = 0x1E
  case BmpDone = 0x20
  case FirmwareInfo = 0x23
  case Heartbeat = 0x25
  case DashConfig = 0x26
  case WearDetection = 0x27  // 01 for on
  case BrightnessState = 0x29
  case GlassesState = 0x2B
  case Battery = 0x2C
  case HeadsUp = 0x32
  case LensSerialNumber = 0x33
  case DeviceSerialNumber = 0x34
  case Uptime = 0x37
  case DashPosition = 0x3B
  case Notif = 0x4B
  case Ping = 0x4D
  case Text = 0x4E
  case NotifConfig = 0x4F
  case FirmwareInfoRes = 0x6E
  case MicData = 0xF1
  case Device = 0xF5
  case NotifSetting = 0xF6
}

func handleUnknownCommands(peripheral: CBPeripheral, data: Data, side: Side, store: JotaiStore) {
  switch data[0] {
  case 0x14:
    // After opening notifications
    // 0x14c9
    break
  case 0x22:
    // log("0x22: \(name) \(data.hex)")
    // Right only
    // TX: 2205 0043 01
    // RX: 2205 0043 0100 0100
    // R: 0x220500e6010301
    //    0x2205003c010301
    //    0x22050044010301
    break
  case 0x2A:
    // After opening settings
    // 0x2a6801
    break
  case 0x3A:
    // After opening settings
    // 0x3ac901
    break
  case 0x39:
    // on dash control
    // 0x390500cf01
    break
  case 0x3E:
    // Very long, only after ping, only right
    // Fetch buried point data, which is essentially user usage tracking: https://www.php.cn/faq/446290.html
    // 0x3ec97bd44...
    break
  case 0x3F:
    // On pairing
    // 0x3f05c9
    break
  case 0x4F:
    // On pairing
    // 0x4fc901
    break
  case 0x50:
    // right only
    // 0x500600000101
    break
  default:
    guard let name = peripheral.name else { return }
    log(
      "unknown command: \(name) \(data[0]) \(data.hex) \(data.subdata(in: 1..<data.count).ascii() ?? "<>")"
    )
    break
  }
}

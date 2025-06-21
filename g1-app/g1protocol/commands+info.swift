import CoreBluetooth
import Foundation
import Log
import jotai

struct Info {
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
let infoListeners: [Cmd: Listener] = [
  Cmd.Error: { (peripheral, data, side, store) in
    guard let name = peripheral.name else { return }
    let code = data[1]
    let msg = data.subdata(in: 2..<data.count).ascii() ?? "<>"
    log("00: \(name) \(code.hex) \(msg)")
  },
  Cmd.Battery: { (peripheral, data, side, store) in
    switch data[1] {
    case 0x66:
      // (Left)
      // 0x2c66 4b 00 d3 94 20 000000 01 05
      // 0x2c66 4b 00 d3 83 20 000000 01 05
      // 0x2c66 4b 00 d4 88 20 000000 01 05
      // (Right)
      // 0x2c66 4d 4c d6 83 1e 01 05 00 01 05
      // 0x2c66 4d 4c d6 83 1e 01 05 00 01 05
      // 0x2c66 4d 4c d6 81 1e 01 05 00 01 05

      // log(
      //   "battery: \(name) \(data[2]), info: \(data.subdata(in: 4..<7).hexSpace)| \(data.hex)"
      // )
      if side == .left {
        store.set(atom: leftBatteryAtom, value: Int(data[2]))
      } else {
        store.set(atom: rightBatteryAtom, value: Int(data[2]))
      }
    default:
      guard let name = peripheral.name else { return }
      log("battery: \(name) \(data.hex)")
    }
  },
  Cmd.GlassesState: { (peripheral, data, side, store) in
    // 0x2b690a0b
    // 0x2b690a07
    // 0x2b690aff
    // Right is sometimes wrong
    guard side == .left else { return }
    guard let name = peripheral.name else { return }
    switch data[3] {
    case 0x06:
      store.set(atom: glassesStateAtom, value: .Wearing)
    case 0x07:
      store.set(atom: glassesStateAtom, value: .Off)
    case 0x08:
      store.set(atom: glassesStateAtom, value: .CaseOpen)
    case 0x0B:
      store.set(atom: glassesStateAtom, value: .CaseClosed)
    case 0xFF:
      log("Glasses turned on")
    default:
      log("UNKNOWN 0x2B: \(name) \(data.hex)")
    }
    if let silentMode = data[2] == 0x0C ? true : data[2] == 0x0A ? false : nil {
      store.set(atom: silentModeAtom, value: silentMode)
    } else {
      log("unknown mode state \(name) \(data.hex)")
    }
  },
  Cmd.FirmwareInfoRes: { (peripheral, data, side, store) in
    // let text = data.ascii() ?? "<>"
    // log("firmware: \(name) \(text.trim())")
  },
  Cmd.LensSerialNumber: { (peripheral, data, side, store) in
    guard let name = peripheral.name else { return }
    let serialNumber = data.subdata(in: 1..<data.count).ascii()
    log("Glasses Serial Number: \(name) \(data.hex) \(serialNumber ?? "nil")")
    let glasses = store.get(atom: glassesModelAtom)
    if side == .left {
      glasses?.leftLensSerialNumber = serialNumber
    } else {
      glasses?.rightLensSerialNumber = serialNumber
    }
  },
  Cmd.DeviceSerialNumber: { (peripheral, data, side, store) in
    guard let name = peripheral.name else { return }
    let serialNumber = data.subdata(in: 1..<data.count).ascii()
    log("Device Serial Number: \(name) \(data.hex) \(serialNumber ?? "nil")")
    let frameCode = data.subdata(in: 2..<6).ascii()
    let colorCode = data.subdata(in: 7..<8).ascii()
    guard let frameCode, let colorCode else { return }
    let frame =
      frameCode == "S100" ? "Round" : frameCode == "S110" ? "Square" : "Unknown " + frameCode
    let color =
      colorCode == "A"
      ? "Grey"
      : colorCode == "B"
        ? "Brown"
        : colorCode == "C" ? "Green" : "Unknown " + colorCode
    log("Frame \(frame), color \(color)")
    let glasses = store.get(atom: glassesModelAtom)
    glasses?.deviceSerialNumber = serialNumber
  },
  Cmd.Uptime: { (peripheral, data, side, store) in
    // time since boot in seconds?
    // 0x3737e1bc000001
  }
]

let leftBatteryAtom = PrimitiveAtom<Int?>(nil)
let rightBatteryAtom = PrimitiveAtom<Int?>(nil)

let silentModeAtom = PrimitiveAtom<Bool>(false)

let glassesStateAtom = PrimitiveAtom(GlassesState.Off)
enum GlassesState {
  case Wearing
  case Off
  case CaseOpen
  case CaseClosed
}

let glassesModelAtom = PrimitiveAtom<GlassesModel?>(nil)

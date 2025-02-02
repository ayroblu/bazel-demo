import Foundation

let uartServiceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
let uartTxCharacteristicUuid = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
let uartRxCharacteristicUuid = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
let smpServiceUuid = "8D53DC1D-1DB7-4CD3-868B-8A527460AA84"
let smpCharacteristicUuid = "DA2E7828-FBCE-4E01-AE9E-261174997C48"

struct G1Cmd {
  struct Exit {
    static func data() -> Data {
      return Data([0x18])
    }
  }
  struct Brightness {
    static func data(brightness: UInt8, auto: Bool) -> Data {
      let brightness: UInt8 = brightness > 63 ? 63 : brightness
      return Data([0x01, brightness, auto ? 1 : 0])
    }
  }
  struct Mic {
    static func data(enable: Bool) -> Data {
      return Data([0x0E, enable ? 1 : 0])
    }
  }
  struct Text {
    static func data(text: String) -> Data? {
      guard let textData = text.data(using: .utf8) else { return nil }
      let cmd = 0x4E
      let seq = 0x00
      let numItems = 0x01
      let item = 0x00
      let newScreen = 0x71  // 0x01 | 0x70, new content | text show
      let newCharPos = [0x00, 0x00]  // Big endian int16
      let pageNum = 0x00
      let pageCount = 0x01

      let controlArr =
        [cmd, seq, numItems, item, newScreen] + newCharPos + [pageNum, pageCount]
      return Data(controlArr.map { UInt8($0) }) + textData
    }
  }
}

import Foundation
import Log
import zlib

let uartServiceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
let uartTxCharacteristicUuid = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
let uartRxCharacteristicUuid = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
let smpServiceUuid = "8D53DC1D-1DB7-4CD3-868B-8A527460AA84"
let smpCharacteristicUuid = "DA2E7828-FBCE-4E01-AE9E-261174997C48"

struct G1Cmd {
  struct Exit {
    static func data() -> Data {
      return Data([SendCmd.Exit.rawValue])
    }
  }
  struct Brightness {
    static func data(brightness: UInt8, auto: Bool) -> Data {
      let brightness: UInt8 = brightness > 63 ? 63 : brightness
      return Data([SendCmd.Brightness.rawValue, brightness, auto ? 1 : 0])
    }
  }
  struct Config {
    static func headTiltData(angle: Int) -> Data? {
      guard angle >= 0 && angle <= 60 else { return nil }
      return Data([SendCmd.HeadTilt.rawValue, UInt8(angle), 0x01])
    }
  }
  struct Mic {
    static func data(enable: Bool) -> Data {
      return Data([SendCmd.Mic.rawValue, enable ? 1 : 0])
    }
    struct MicResp {
      let isSuccess: Bool
      let enable: Bool
    }
    static func respData(data: Data) -> MicResp {
      // 0xCA is technically failure
      return MicResp(isSuccess: data[1] == 0xC9 ? true : false, enable: data[2] == 1)
    }
  }
  struct Text {
    static func data(text: String) -> Data? {
      guard let textData = text.data(using: .utf8) else { return nil }
      let cmd = SendCmd.Text.rawValue
      let seq: UInt8 = 0x00
      let numItems: UInt8 = 0x01
      let item: UInt8 = 0x00
      let newScreen: UInt8 = 0x71  // 0x01 | 0x70, new content | text show
      let newCharPos: [UInt8] = [0x00, 0x00]  // Big endian int16
      let pageNum: UInt8 = 0x00
      let pageCount: UInt8 = 0x01

      let controlArr =
        [cmd, seq, numItems, item, newScreen] + newCharPos + [pageNum, pageCount]
      return Data(controlArr) + textData
    }
  }
  struct Bmp {
    static let maxLength = 194
    static let address: [UInt8] = [0x00, 0x1C, 0x00, 0x00]
    static func data(image: Data) -> [Data] {
      let cmd = SendCmd.Bmp.rawValue
      return image.chunk(into: maxLength).enumerated().map { (seq, chunk) in
        let address: [UInt8] = seq == 0 ? address : []
        let controlarr: [UInt8] = [cmd, UInt8(seq)] + address
        return Data(controlarr) + chunk
      }
    }
    static func endData() -> Data {
      return Data([0x20, 0x0D, 0x0E])
    }
    static func crcData(inputData: Data) -> Data {
      let crc: UInt32 = (address + inputData).toCrc32()
      // flutter: 2025-02-02 22:55:30.917743 Crc32Xz---lr---R---ret--------[22, 194, 143, 65, 67, 202, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]------crc----[194, 143, 65, 67]--
      // [194, 143, 65, 67]
      log("crc data", crc.bytes())
      return Data([BLE_REC.CRC.rawValue] + crc.bytes())
    }
    static func crcResp(data: Data) -> Bool {
      // true is failure
      // 0x16c28f4143ca
      // [22, 194, 143, 65, 67, 202]
      // let a = Data([22, 194, 143, 65, 67, 202])
      // log("crc resp original", a.hex)
      return data.count > 4 && data[5] != 0xC9
    }
  }
  struct Heartbeat {
    static private var heartbeatSeq: UInt8 = 0x00
    static func data() -> Data {
      let length: UInt8 = 6
      let dataArr: [UInt8] = [
        0x25,
        length & 0xff,
        (length >> 8) & 0xff,
        heartbeatSeq,
        0x04,
        heartbeatSeq,
      ]
      let data = Data(dataArr)
      heartbeatSeq = (heartbeatSeq + 1) & 0xFF
      return data
    }
  }
  struct Notify {
    static var notifyId: UInt8 = 0x00
    static func allowData(id: String, name: String) -> [Data] {
      let dict: [String: Any] = [
        "calendar_enable": true,
        "call_enable": true,
        "msg_enable": true,
        "ios_mail_enable": true,
        "app": [
          "list": [["id": id, "name": name]],
          "enable": true,
        ],
      ]

      guard let json = toJson(dict: dict) else { return [] }
      let chunks = json.chunk(into: 177)
      let numItems: UInt8 = UInt8(chunks.count)
      log("allowData numItems: \(numItems), dataSize: \(json.count)", json.ascii() ?? "<>")
      let result = chunks.enumerated().map { (index, chunk) in
        Data([SendCmd.AddNotif.rawValue, numItems, UInt8(index)]) + chunk
      }
      return result
    }
    static func data(notifyData: NotifyData) -> [Data] {
      let dict = [
        "ncs_notification": [
          "msg_id": 1_234_567_890, "app_identifier": "com.even.test", "title": "Even Realities",
          "subtitle": "Notify", "message": "This is a notification",
          "time_s": Int(Date().timeIntervalSince1970 * 1000),
          "display_name": "Even",
        ]
      ]
      // let dict: [String: Any] = [
      //   "ncs_notification": [
      //     "msg_id": notifyData.msgId,
      //     "app_identifier": notifyData.appIdentifier,
      //     "title": notifyData.title,
      //     "subtitle": notifyData.subtitle ?? "",
      //     "message": notifyData.message ?? "",
      //     "time_s": notifyData.timestamp,
      //     "display_name": notifyData.displayName,
      //   ]
      // ]
      guard let json = toJson(dict: dict) else { return [] }
      log("JSON", String(data: json, encoding: .utf8) ?? "?")
      let chunks = json.chunk(into: 176)
      let numItems: UInt8 = UInt8(chunks.count)
      let result = chunks.enumerated().map { (index, chunk) in
        Data([SendCmd.Notif.rawValue, notifyId, numItems, UInt8(index)]) + chunk
      }
      notifyId = (notifyId + 1) & 0xFF
      return result
    }
  }
}

struct NotifyData {
  let msgId: Int = 1_234_567_890
  let appIdentifier: String = Info.id
  let title: String
  var subtitle: String?
  var message: String?
  let timestamp: Int = Int(Date().timeIntervalSince1970 * 1000)
  let displayName: String = Info.name
}

enum SendCmd: UInt8 {
  case Brightness = 0x01
  case AddNotif = 0x04
  case HeadTilt = 0x0B
  case Mic = 0x0E
  case Exit = 0x18
  case FirmwareInfo = 0x23
  case Text = 0x4E
  case Bmp = 0x15
  case Crc = 0x16
  case Notif = 0x4B
  case Ping = 0x4D
}
enum BLE_REC: UInt8 {
  case ERROR = 0x00
  case AddNotif = 0x04
  case HeadTilt = 0x0B
  case MIC = 0x0E
  case MIC_DATA = 0xF1
  case DEVICE = 0xF5
  case BATTERY = 0x2C
  case FIRMWARE_INFO_RES = 0x6E
  case CRC = 0x16
  case Exit = 0x18
  case BmpDone = 0x20
  case HEARTBEAT = 0x25
  case NOTIF = 0x4B
  case PING = 0x4D
  case TEXT = 0x4E
  case NOTIF_SETTING = 0xF6
  case UNKNOWN_06 = 0x06
  case UNKNOWN_08 = 0x08
  case UNKNOWN_14 = 0x14
  case UNKNOWN_1E = 0x1E
  case UNKNOWN_22 = 0x22
  case UNKNOWN_26 = 0x26
  case UNKNOWN_29 = 0x29
  case UNKNOWN_2A = 0x2A
  case UNKNOWN_2B = 0x2B
  case UNKNOWN_32 = 0x32
  case UNKNOWN_3A = 0x3A
  case UNKNOWN_37 = 0x37
  case UNKNOWN_39 = 0x39
  case UNKNOWN_3B = 0x3B
  case UNKNOWN_3E = 0x3E
  case UNKNOWN_3F = 0x3F
  case UNKNOWN_4F = 0x4F
  case UNKNOWN_50 = 0x50
}
enum DEVICE_CMD: UInt8 {
  case SINGLE_TAP = 0x01
  case DOUBLE_TAP = 0x00
  case TRIPLE_TAP = 0x04  // or 05??
  case LOOK_UP = 0x02
  case LOOK_DOWN = 0x03
  case DASH_SHOWN = 0x1E
  case DASH_HIDE = 0x1F
  case CASE_EXIT = 0x07
  case CASE = 0x08
  case CASE_CLOSE = 0x0B
  case CASE_STATE = 0x0E
  case CASE_BATTERY = 0x0F
  case UNKNOWN_06 = 0x06
  case UNKNOWN_09 = 0x09
  case UNKNOWN_0A = 0x0A
  case UNKNOWN_11 = 0x11
  case UNKNOWN_12 = 0x12
}

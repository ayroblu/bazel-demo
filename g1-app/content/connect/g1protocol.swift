import Foundation
import Log
import utils
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
  struct Info {
    static func batteryData(battery: Bool) -> Data {
      return Data([SendCmd.Battery.rawValue, 0x02])
    }
    static func glassesStateData() -> Data {
      return Data([SendCmd.GlassesState.rawValue])
    }
    static func firmwareData() -> Data {
      return Data([SendCmd.FirmwareInfo.rawValue, 0x74])
    }
  }
  struct Config {
    static func brightnessData(brightness: UInt8, auto: Bool) -> Data {
      let brightness: UInt8 = brightness > 63 ? 63 : brightness
      return Data([SendCmd.Brightness.rawValue, brightness, auto ? 1 : 0])
    }
    static func silentModeData(enabled: Bool) -> Data {
      return Data([SendCmd.SilentMode.rawValue, enabled ? 0x0C : 0x0A, 0x00])
    }
    enum DashMode: UInt8 {
      case Full = 0x00
      case Dual = 0x01
      case Minimal = 0x02
    }
    enum DashSubMode: UInt8 {
      case Notes = 0x00
      case Stock = 0x01
      case News = 0x02
      case Calendar = 0x03
      case Navigation = 0x04
      case Map = 0x05
    }
    static func dashModeData(mode: DashMode, subMode: DashSubMode) -> Data {
      return Data([
        SendCmd.DashMode.rawValue, 0x07, 0x00, 0x06, mode.rawValue,
        mode == DashMode.Minimal ? 0x00 : subMode.rawValue,
      ])
    }
    enum WeatherIcon: UInt8 {
      case Night = 0x01
      case Clouds = 0x02
      case Drizzle = 0x03
      case HeavyDrizzle = 0x04
      case Rain = 0x05
      case HeavyRain = 0x06
      case Thunder = 0x07
      case ThunderStorm = 0x08
      case Snow = 0x09
      case Mist = 0x0A
      case Fog = 0x0B
      case Sand = 0x0C
      case Squalls = 0x0D
      case Tornado = 0x0E
      case Freezing = 0x0F
      case Sunny = 0x10
    }
    static func dashTimeWeatherData(weatherIcon: WeatherIcon, temp: UInt8) -> Data {
      let currentTime = Date().timeIntervalSince1970
      let epochTime32: [UInt8] = withUnsafeBytes(of: Int32(currentTime)) { Array($0) }
      let epochTime64: [UInt8] = withUnsafeBytes(of: Int64(currentTime * 1000)) { Array($0) }
      let fahrenheit: UInt8 = 0x00  // 00 is C, 01 is F
      let twelveHour: UInt8 = 0x00  // 00 is 24h, 01 is 12h
      return Data(
        [
          SendCmd.DashMode.rawValue, 0x15, 0x00, 0x03,
        ] + epochTime32 + epochTime64 + [
          weatherIcon.rawValue, temp, fahrenheit, twelveHour,
        ])
    }
    static func headTiltData(angle: Int) -> Data? {
      guard angle >= 0 && angle <= 60 else { return nil }
      return Data([SendCmd.HeadTilt.rawValue, UInt8(angle), 0x01])
    }
    static func dashData(isShow: Bool, vertical: UInt8, distance: UInt8) -> Data? {
      let cmd: UInt8 = 0x02
      let show: UInt8 = isShow ? 0x01 : 0x00
      guard vertical >= 1 && vertical <= 0x08 else { return nil }
      // distance is 1-5m in 0.5m increments
      guard distance >= 1 && distance <= 0x09 else { return nil }
      return Data([
        SendCmd.DashConfig.rawValue, 0x08, 0x00, 0x01,
        cmd, show, vertical, distance,
      ])
    }
    struct Event {
      let name: String
      let time: String
      let location: String
    }
    static func calendarData(event: Event) -> Data {
      let nameData: [UInt8] = event.name.uint8()
      let nameLength: UInt8 = UInt8(nameData.count)
      let timeData: [UInt8] = event.time.uint8()
      let timeLength: UInt8 = UInt8(timeData.count)
      let locationData: [UInt8] = event.location.uint8()
      let locationLength: UInt8 = UInt8(locationData.count)
      let fixedData: [UInt8] = [
        0x00, 0x99, 0x03, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x03, 0x01,
      ]
      // need part + event data split for swift type checker
      let partData: [UInt8] = fixedData + [0x01, nameLength] + nameData
      let partData2: [UInt8] = partData + [0x02, timeLength] + timeData
      let eventData: [UInt8] = partData2 + [0x03, locationLength] + locationData
      let totalLength: UInt8 = UInt8(eventData.count + 2)
      log("calendar length", eventData.count)
      return Data([SendCmd.DashMode.rawValue, totalLength] + eventData)
    }
    struct Note {
      let title: String
      let text: String
    }
    static var noteId: UInt8 = 0x00
    static func notesData(notes: [Note]) -> [Data] {
      return (0..<4).map { idx in
        noteId = (noteId + 1) & 0xFF
        let noteIdx: UInt8 = UInt8(idx + 1)
        if let note = notes[safe: idx] {
          let titleData: [UInt8] = note.title.uint8()
          let titleLength: UInt8 = UInt8(titleData.count)
          let textData: [UInt8] = note.text.uint8()
          let textLength: UInt8 = UInt8(textData.count)
          let noteData: [UInt8] =
            [0x00, noteId, 0x03, 0x01, 0x00, 0x01, 0x00, noteIdx, 0x01, titleLength] + titleData
            + [textLength, 0x00] + textData
          let totalLength: UInt8 = UInt8(noteData.count + 2)
          return Data([SendCmd.Notes.rawValue, totalLength] + noteData)
        } else {
          let noteData: [UInt8] = [
            0x00, noteId, 0x03, 0x01, 0x00, 0x01, 0x00, noteIdx, 0x00,
            0x01, 0x00, 0x01, 0x00, 0x00,
          ]
          let totalLength: UInt8 = UInt8(noteData.count + 2)
          return Data([SendCmd.Notes.rawValue, totalLength] + noteData)
        }
      }
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
  struct Navigate {
    static var seqId: UInt8 = 0x00
    static func data(id: String, name: String) -> [Data] {
      let partType0: UInt8 = 0x00
      let partType1: UInt8 = 0x01
      let partType2: UInt8 = 0x02
      let partType3: UInt8 = 0x03
      let numPackets: UInt8 = 0x01
      let packetNum: UInt8 = 0x00
      let arrivedTitle: Data = "Arrived".data()
      let arrivedMessage: Data = "Your destination is on the right".data()
      let distance: Data = "0 m".data()
      let speed: Data = "9.8km/h".data()
      let data0 = Data([0x0A, 0x06, 0x00, seqId, partType0])
      seqId += 1
      let NULL = Data([0x00])
      let data1 =
        Data([
          0x0A, 0x40, 0x00, seqId, partType1, 0x02, 0x00, 0xCC,
          0x00, 0x73, 0x00,
        ]) + arrivedTitle + NULL + NULL + arrivedMessage + NULL + distance + NULL + speed + NULL
      seqId += 1
      let data2 =
        Data([
          0x0A, 0x40, 0x00, seqId, partType2, numPackets, 0x00, packetNum, 0x0,
          // TODO
        ])
      seqId += 1
      let data3 =
        Data([
          0x0A, 0x40, 0x00, seqId, partType3, numPackets, 0x00, packetNum, 0x0,
          // TODO
        ])
      return [
        data0,
        data1,
        data2,
        data3,
      ]
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
  case SilentMode = 0x03
  case AddNotif = 0x04
  case DashMode = 0x06
  case HeadTilt = 0x0B
  case Mic = 0x0E
  case Bmp = 0x15
  case Crc = 0x16
  case Exit = 0x18
  case Notes = 0x1E
  case FirmwareInfo = 0x23
  case DashConfig = 0x26
  case WearDetection = 0x27  // 01 for on
  case BrightnessState = 0x29
  case GlassesState = 0x2B
  case Battery = 0x2C
  case Uptime = 0x37
  case Text = 0x4E
  case Notif = 0x4B
  case Ping = 0x4D
}
enum BLE_REC: UInt8 {
  case ERROR = 0x00
  case AutoBrightness = 0x01
  case SilentMode = 0x03
  case AddNotif = 0x04
  case DashMode = 0x06
  case HeadTilt = 0x0B
  case DashConfig = 0x26
  case MIC = 0x0E
  case MIC_DATA = 0xF1
  case DEVICE = 0xF5
  case BATTERY = 0x2C
  case FIRMWARE_INFO_RES = 0x6E
  case CRC = 0x16
  case Exit = 0x18
  case BmpDone = 0x20
  case HEARTBEAT = 0x25
  case GlassesState = 0x2B
  case Uptime = 0x37
  case NOTIF = 0x4B
  case PING = 0x4D
  case TEXT = 0x4E
  case NOTIF_SETTING = 0xF6
}
enum DEVICE_CMD: UInt8 {
  case SINGLE_TAP = 0x01
  case DOUBLE_TAP = 0x00
  case TRIPLE_TAP_SILENT = 0x04
  case TRIPLE_TAP_NORMAL = 0x05
  case LOOK_UP = 0x02
  case LOOK_DOWN = 0x03
  case DASH_SHOWN = 0x1E
  case DASH_HIDE = 0x1F
  case CASE_OPEN = 0x08
  case CASE_CLOSE = 0x0B
  case CASE_STATE = 0x0E
  case CASE_BATTERY = 0x0F
  case WEAR_ON = 0x06
  case WEAR_OFF = 0x07
  case UNKNOWN_09 = 0x09
  case UNKNOWN_0A = 0x0A
  case UNKNOWN_11 = 0x11
  case UNKNOWN_12 = 0x12
}

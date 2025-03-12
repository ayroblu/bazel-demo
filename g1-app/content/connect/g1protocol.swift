import CoreBluetooth
import Foundation
import Log
import Pcm
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
      let currentTime = Date().adjustToCurrentTimeZone().timeIntervalSince1970
      let epochTime32: [UInt8] = withUnsafeBytes(of: Int32(currentTime)) { Array($0) }
      let epochTime64: [UInt8] = withUnsafeBytes(of: Int64(currentTime * 1000)) { Array($0) }
      let fahrenheit: UInt8 = 0x00  // 00 is C, 01 is F
      let twelveHour: UInt8 = 0x00  // 00 is 24h, 01 is 12h
      // Value: 0615 0007 013B 1ECA 6723 1786 6D95 0100 0001 0B00 00
      return Data(
        [
          SendCmd.DashMode.rawValue, 0x15, 0x00, 0x07, 0x01,
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
        noteId &+= 1
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
        // Checksum? Maybe just length
        // Send:    1E06 003F 0101
        // Receive: 1E06 0009 0100
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
        length,
        length >> 8,
        heartbeatSeq,
        0x04,
        heartbeatSeq,
      ]
      let data = Data(dataArr)
      heartbeatSeq &+= 1
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
      notifyId &+= 1
      return result
    }
  }
  struct Navigate {
    static var seqId: UInt8 = 0x00
    static func parseExampleImage(image: String) -> [Bool] {
      return image.parseHex().convertToBits()
    }
    static func exampleData() -> [Data] {
      return [initData(), directionsDataExample()]
        + primaryImageData(
          image: parseExampleImage(image: exampleImage1),
          overlay: parseExampleImage(image: exampleImage1Overlay))
        + secondaryImageData(
          image: parseExampleImage(image: exampleImage2),
          overlay: parseExampleImage(image: exampleImage2Overlay))
    }
    static func initData() -> Data {
      // Note saw also right before start:
      // Both: [0x39, 0x05, 0x00, 0x7C, 0x01]
      // Right: [0x50, 0x06, 0x00, 0x00, 0x01, 0x01]
      let part: [UInt8] = [0x00, seqId, 0x00, 0x01]
      let data = Data([SendCmd.Navigate.rawValue, UInt8(part.count + 2)] + part)
      seqId &+= 1
      return data
    }
    static func directionsDataExample() -> Data {
      // x is 0 -> 488
      // y is 0 -> 136
      return directionsData(
        totalDuration: "6min", totalDistance: "529m", direction: "Turn right onto the walkway",
        distance: "18 m", speed: "0km/h", x: 488.bytes(byteCount: 2), y: 0x00)
    }
    static func directionsData(
      totalDuration: String, totalDistance: String, direction: String, distance: String,
      speed: String, x: [UInt8], y: UInt8
    ) -> Data {
      let totalDurationData: [UInt8] = totalDuration.uint8()
      let totalDistanceData: [UInt8] = totalDistance.uint8()
      let directionData: [UInt8] = direction.uint8()
      let distanceData: [UInt8] = distance.uint8()
      let speedData: [UInt8] = speed.uint8()

      let part0: [UInt8] = [0x00, seqId, 0x01, 0x03] + x + [y, 0x00]
      let part: [UInt8] =
        part0 + totalDurationData + nullArr + totalDistanceData + nullArr
        + directionData + nullArr + distanceData + nullArr + speedData + nullArr
      let data = Data([SendCmd.Navigate.rawValue, UInt8(part.count + 2)] + part)
      return data
    }
    static func primaryImageData(image: [Bool], overlay: [Bool]) -> [Data] {
      // image and overlay must be 136 * 136 long
      let partType2: UInt8 = 0x02
      let imageBytes: [UInt8] = (image + overlay).toBytes().runLengthEncode()
      let maxLength = 185
      let chunks = imageBytes.chunk(into: maxLength)
      let packetCount: UInt8 = UInt8(chunks.count)
      return chunks.enumerated().map { (index, chunk) in
        let packetNum: UInt8 = UInt8(index + 1)
        let part: [UInt8] = [null, seqId, partType2, packetCount, null, packetNum, null] + chunk
        seqId &+= 1
        return Data([SendCmd.Navigate.rawValue, UInt8(part.count + 2)] + part)
      }
    }
    static func secondaryImageData(image: [Bool], overlay: [Bool]) -> [Data] {
      // image must be 488 * 136 (w x h)
      let partType3: UInt8 = 0x03
      let imageBytes: [UInt8] = (image + overlay).toBytes()
      let maxLength = 185
      let chunks = imageBytes.chunk(into: maxLength)
      let packetCount: UInt8 = UInt8(chunks.count)
      return chunks.enumerated().map { (index, chunk) in
        let packetNum: UInt8 = UInt8(index + 1)
        let part: [UInt8] =
          [null, seqId, partType3, packetCount, null, packetNum, null, null] + chunk
        seqId &+= 1
        return Data([SendCmd.Navigate.rawValue, UInt8(part.count + 2)] + part)
      }
    }
    static var pollerSeqId: UInt8 = 0x01
    static func pollerData() -> Data {
      let partType4: UInt8 = 0x04
      let part: [UInt8] = [null, seqId, partType4, pollerSeqId]
      seqId &+= 1
      pollerSeqId &+= 1
      let data = Data([SendCmd.Navigate.rawValue, UInt8(part.count + 2)] + part)
      return data
    }
    static func endData() -> Data {
      let partType5: UInt8 = 0x05
      let part: [UInt8] = [null, seqId, partType5, 0x01]
      seqId &+= 1
      return Data([SendCmd.Navigate.rawValue, UInt8(part.count + 2)] + part)
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
enum GlassesState {
  case Wearing
  case Off
  case CaseOpen
  case CaseClosed
}

enum SendCmd: UInt8 {
  case Brightness = 0x01
  case SilentMode = 0x03
  case AddNotif = 0x04
  case DashMode = 0x06
  case Navigate = 0x0A
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
  case DashPosition = 0x3B
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
  case Navigate = 0x0A
  case HeadTilt = 0x0B
  case Notes = 0x1E
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
  case DashPosition = 0x3B
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

func onValue(_ peripheral: CBPeripheral, data: Data, mainVm: MainVM?) {
  let isLeft = peripheral == mainVm?.connectionManager.manager.leftPeripheral
  guard let name = peripheral.name else { return }
  let rspCommand = BLE_REC(rawValue: data[0])
  switch rspCommand {
  case .ERROR:
    let code = data[1]
    let msg = data.subdata(in: 2..<data.count).ascii() ?? "<>"
    log("00: \(name) \(code.hex) \(msg)")
    break
  case .AutoBrightness:
    // 0x01c9
    logFailure(code: data[1], type: "autobrightness", name: name, data: data)
  case .SilentMode:
    // 0x03c9
    logFailure(code: data[1], type: "silent mode", name: name, data: data)
  case .AddNotif:
    // 0x04ca
    logFailure(code: data[1], type: "add notif", name: name, data: data)
  case .DashMode:
    switch data[1] {
    case 0x07:
      // mode: (full dual minimal)
      // 0x0607003b06
      break
    case 0x15:
      // dash time and weather
      // 0x0615003801
      break
    default:
      // Probably calendar?
      // log("unknown dash cmd: \(name) \(data.hex)")
      break
    }
  case .Navigate:
    // response to navigation requests
    break
  case .MIC:
    let resp = G1Cmd.Mic.respData(data: data)
    log("mic action success: \(resp.isSuccess), enabled: \(resp.enable)")
  case .MIC_DATA:
    let effectiveData = data.subdata(in: 2..<data.count)
    let pcmConverter = PcmConverter()
    let pcmData = pcmConverter.decode(effectiveData)

    let inputData = pcmData as Data
    mainVm?.connectionManager.speechRecognizer?.appendPcmData(inputData)
  case .CRC:
    if G1Cmd.Bmp.crcResp(data: data) {
      log("CRC check failed", data.hex)
    } else {
      log("CRC success")
    }
  case .Notes:
    // response to note update
    // Only the data[1] and data[3] changes, reflecting the original message (packet length and sequence number)
    // 1E10 003E 0301 0001 0000
    // 0x1e06001c01
    // log("0x1E: \(name) \(data.hex)")
    break
  case .GlassesState:
    // 0x2b690a0b
    // 0x2b690a07
    // Right is sometimes wrong
    if !isLeft {
      break
    }
    switch data[3] {
    case 0x06:
      mainVm?.glassesState = .Wearing
    case 0x07:
      mainVm?.glassesState = .Off
    case 0x08:
      mainVm?.glassesState = .CaseOpen
    case 0x0B:
      mainVm?.glassesState = .CaseClosed
    default:
      log("UNKNOWN 0x2B: \(name) \(data.hex)")
    }
    if let silentMode = data[2] == 0x0C ? true : data[2] == 0x0A ? false : nil {
      mainVm?.silentMode = silentMode
    } else {
      log("unknown mode state \(name) \(data.hex)")
    }
  case .Uptime:
    // time since boot in seconds?
    // 0x3737e1bc000001
    break
  case .DashPosition:
    // on load, right only
    // 0x3bc90203
    if data[1] == 0xC9 {
      mainVm?.dashVertical = data[2]
      mainVm?.dashDistance = data[3]
    }
    break
  case .DEVICE:
    // let isLeft = peripheral.identifier.uuidString == "left-uuid"
    let cmd = DEVICE_CMD(rawValue: data[1])
    switch cmd {
    case .SINGLE_TAP:
      log("single tap!", name)
    case .DOUBLE_TAP:
      log("double tap!", name)
    case .TRIPLE_TAP_SILENT:
      log("silent mode on", name)
    case .TRIPLE_TAP_NORMAL:
      log("not silent mode", name)
    case .LOOK_UP:
      log("look up", name, data.hex)
      mainVm?.connectionManager.syncEvents()
      mainVm?.connectionManager.checkWeather()

    // let text = "Looked up!"
    // guard let textData = G1Cmd.Text.data(text: text) else { break }
    // manager.transmitBoth(textData)
    case .LOOK_DOWN:
      log("look down", name, data.hex)
    // let text = "Looked down!"
    // guard let textData = G1Cmd.Text.data(text: text) else { break }
    // manager.transmitBoth(textData)
    case .DASH_SHOWN:
      log("dash shown", name, data.hex)
    case .DASH_HIDE:
      log("dash hide", name, data.hex)
    case .CASE_OPEN:
      log("case open", data.hex)
      mainVm?.glassesState = .CaseOpen
    case .CASE_CLOSE:
      log("case close", data.hex)
      mainVm?.glassesState = .CaseClosed
    case .CASE_STATE:
      log("case is open: \(data[2])")
      // mainVm?.glassesState = data[2] == 1 ? GlassesState.CaseOpen : GlassesState.CaseClosed
      // 0xf50e01
      break
    case .CASE_BATTERY:
      log("case battery: \(data[2])")
      mainVm?.caseBattery = Int(data[2])
      // 0xf50f46
      break
    case .WEAR_ON:
      log("wear on: \(name) \(data.hex)")
      mainVm?.glassesState = .Wearing
      mainVm?.connectionManager.sendWearMessage()
      // 0xf506
      break
    case .WEAR_OFF:
      log("wear off: \(name) \(data.hex)")
      // wear off is also not in case
      mainVm?.glassesState = .Off
      // 0xf507
      break
    case .UNKNOWN_09:
      // 0xf50901
      break
    case .UNKNOWN_0A:
      // 0xf50a64
      break
    case .UNKNOWN_11:
      // L only, after Ping
      // 0xf511
      break
    case .UNKNOWN_12:
      // R Only
      // 0xf51206
      // 0xf5120c
      break
    case .none:
      switch data[1] {
      case 0x00:
        break
      default:
        log("unknown device command: \(name) \(data[1]) \(data.hex)")
        break
      }
    }
  case .BATTERY:
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
      if isLeft {
        mainVm?.leftBattery = Int(data[2])
      } else {
        mainVm?.rightBattery = Int(data[2])
      }
    default:
      log("battery: \(name) \(data.hex)")
    }
  case .FIRMWARE_INFO_RES:
    // let text = data.ascii() ?? "<>"
    // log("firmware: \(name) \(text.trim())")
    break
  case .HeadTilt:
    // Right only
    // 0x0bc9
    logFailure(code: data[1], type: "head tilt", name: name, data: data)
  case .DashConfig:
    // dash control
    // 0x2606000102c9
    // log("dash control \(data.hex)")
    break
  case .BmpDone:
    log("bmp done \(name), isSuccess: \(data[1] == 0xC9)")
    break
  case .NOTIF:
    let isSuccess = data[1] == 0xC9 || data[1] == 0xCB
    log("notif \(name), isSuccess: \(isSuccess), \(data.hex)")
  case .HEARTBEAT:
    // log("got heartbeat", data.hex)
    break
  case .PING:
    log("ping", data.hex)
    break
  case .TEXT:
    // 0x4ec90001
    break
  case .Exit:
    // ack exit
    // 0x18c9
    break
  case .NOTIF_SETTING:
    // New App notif discovered:
    // {"whitelist_app_add": {"app_identifier":  "com.ayroblu.g1-app","display_name": "G1 Bazel App"}}
    let parts = data[1]
    let seq = data[2]
    let rest = data.subdata(in: 3..<data.count)
    if seq == 0 {
      f6Data[peripheral] = [rest]
    } else {
      if var list = f6Data[peripheral], list.count == seq {
        list.append(rest)
        f6Data[peripheral] = list
      }
    }
    if let list = f6Data[peripheral], seq == parts - 1 {
      let data = Data(list.joined())
      log("0xF6: \(name) [\(data.count)]", data.ascii() ?? "<>")
    }
    break
  case .none:
    switch data[0] {
    case 0x08:
      // on pairing
      // 0x0806000004
      break
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
    case 0x29:
      // On open even app from [0x29] send
      let brightness = data[2]
      let isAutoBrightness = data[3] == 0x01
      // Max brightness: 42
      mainVm?.brightness = brightness
      mainVm?.autoBrightness = isAutoBrightness
    // log("auto brightness \(name) \(brightness) \(isAutoBrightness) | \(data.hex)")
    case 0x2A:
      // After opening settings
      // 0x2a6801
      break
    case 0x32:
      // Right only after opening settings
      // 0x326d1501
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
      log(
        "unknown command: \(name) \(data[0]) \(data.hex) \(data.subdata(in: 1..<data.count).ascii() ?? "<>")"
      )
      break
    }
  }
}
var f6Data: [CBPeripheral: [Data]] = [:]
let nullArr: [UInt8] = [0x00]
let null: UInt8 = 0x00
func logFailure(code: UInt8, type: String, name: String, data: Data) {
  switch RespCode(rawValue: code) {
  case .Success:
    break
  case .Continue:
    break
  case .Failure, .none:
    log("failure: \(type) \(name) \(data.hex)")
  }
}
enum RespCode: UInt8 {
  case Success = 0xC9
  case Continue = 0xCA
  case Failure = 0xCB
}

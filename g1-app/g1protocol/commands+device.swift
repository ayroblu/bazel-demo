import CoreBluetooth
import Foundation
import Log
import Jotai

public struct Device {
  public static func exitData() -> Data {
    return Data([Cmd.Exit.rawValue])
  }
  public struct Mic {
    public static func data(enable: Bool) -> Data {
      return Data([Cmd.Mic.rawValue, enable ? 1 : 0])
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
  public struct Text {
    public static func data(text: String) -> Data? {
      guard let textData = text.data(using: .utf8) else { return nil }
      let cmd = Cmd.Text.rawValue
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

  public struct Teleprompt {
    static private var seq: UInt8 = 0x00
    public static func data(
      isFirst: Bool, visibleText: String, nextText: String, completedPercent: UInt8
    )
      -> [Data]?
    {
      guard let visibleTextData = visibleText.data(using: .utf8) else { return nil }
      guard let nextTextData = nextText.data(using: .utf8) else { return nil }
      let newScreen: UInt8 = isFirst ? 0x01 : 0x07  // manual is 03
      let unknown1: UInt8 = isFirst ? 0x08 : null
      let parts = [visibleTextData, nextTextData]
      let numPackets: UInt8 = UInt8(parts.count)
      return parts.enumerated().map { (index, part) in
        let partIdx: UInt8 = UInt8(index + 1)
        let controlArr: [UInt8] =
          [null, seq, newScreen, numPackets, null, partIdx, null, completedPercent, unknown1, null]
        seq &+= 1
        let len: UInt8 = UInt8(controlArr.count + part.count + 2)
        return Data([Cmd.Teleprompter.rawValue, len] + controlArr) + part
      }
    }

    public static func customEndData() -> Data {
      let messageData: Data = "Teleprompt Closed".data(using: .utf8)!
      let manualCmd: UInt8 = 0x03
      let numPackets: UInt8 = 0x01
      let partIdx = numPackets
      let completedPercent: UInt8 = 0x64  // 100
      let controlArr: [UInt8] =
        [null, seq, manualCmd, numPackets, null, partIdx, null, completedPercent, null, null]
      seq &+= 1
      let lf: UInt8 = 0x0A
      let space: UInt8 = 0x20
      let spaces = Array(repeating: space, count: 19)
      let mainData = Data(controlArr + [lf, lf] + spaces) + messageData + Data(spaces)
      let len: UInt8 = UInt8(mainData.count + 2)
      return Data([Cmd.Teleprompter.rawValue, len] + mainData)
    }

    public static func endData() -> Data {
      let cmd: UInt8 = 0x06
      let subCmd: UInt8 = 0x05  // 1248 bit mask maybe?
      let finish: UInt8 = 0x01
      return Data([Cmd.Teleprompter.rawValue, cmd, null, seq, subCmd, finish])
    }
  }

  public struct Bmp {
    static let maxLength = 194
    static let address: [UInt8] = [0x00, 0x1C, 0x00, 0x00]
    public static func data(image: Data) -> [Data] {
      let cmd = Cmd.Bmp.rawValue
      return image.chunk(into: maxLength).enumerated().map { (seq, chunk) in
        let address: [UInt8] = seq == 0 ? address : []
        let controlarr: [UInt8] = [cmd, UInt8(seq)] + address
        return Data(controlarr) + chunk
      }
    }
    public static func endData() -> Data {
      return Data([Cmd.BmpDone.rawValue, 0x0D, 0x0E])
    }
    public static func crcData(inputData: Data) -> Data {
      let crc: UInt32 = (address + inputData).toCrc32()
      log("crc data", crc.bytes())
      return Data([Cmd.Crc.rawValue] + crc.bytes())
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
  public struct Heartbeat {
    static private var heartbeatSeq: UInt8 = 0x00
    public static func data() -> Data {
      let length: UInt8 = 6
      let dataArr: [UInt8] = [
        Cmd.Heartbeat.rawValue,
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
  public struct Notify {
    static var notifyId: UInt8 = 0x00
    public struct NotifConfig {
      let calendar: Bool
      let call: Bool
      let msg: Bool
      let iosMail: Bool
      let apps: [(id: String, name: String)]?
      public init(
        calendar: Bool, call: Bool, msg: Bool, iosMail: Bool, apps: [(id: String, name: String)]?
      ) {
        self.calendar = calendar
        self.call = call
        self.msg = msg
        self.iosMail = iosMail
        self.apps = apps
      }

    }
    public static func allowData(notifConfig: NotifConfig) -> [Data] {
      let dict: [String: Any] = [
        "calendar_enable": notifConfig.calendar,
        "call_enable": notifConfig.call,
        "msg_enable": notifConfig.msg,
        "ios_mail_enable": notifConfig.iosMail,
        "app": [
          "list": notifConfig.apps?.map { (id, name) in ["id": id, "name": name] } ?? [],
          "enable": notifConfig.apps != nil,
        ],
      ]

      guard let json = toJson(dict: dict) else { return [] }
      let chunks = json.chunk(into: 177)
      let numItems: UInt8 = UInt8(chunks.count)
      log("allowData numItems: \(numItems), dataSize: \(json.count)", json.ascii() ?? "<>")
      let result = chunks.enumerated().map { (index, chunk) in
        Data([Cmd.AddNotif.rawValue, numItems, UInt8(index)]) + chunk
      }
      return result
    }

    public struct NotifyData {
      let appIdentifier: String = Bundle.main.bundleIdentifier ?? ""
      let title: String
      let subtitle: String
      let message: String
      let timestamp: UInt64 = UInt64(Date().timeIntervalSince1970) * 1000
      let displayName: String =
        Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? ""
      public init(title: String, subtitle: String, message: String) {
        self.title = title
        self.subtitle = subtitle
        self.message = message
      }
    }
    public static func data(notifyData: NotifyData) -> [Data] {
      let dict: [String: Any] = [
        "ncs_notification": [
          "msg_id": 1_234_567_890,
          "app_identifier": notifyData.appIdentifier,
          "title": notifyData.title,
          "subtitle": notifyData.subtitle,
          "message": notifyData.message,
          "time_s": notifyData.timestamp,
          "display_name": notifyData.displayName,
        ]
      ]
      guard let json = toJson(dict: dict) else { return [] }
      log("JSON", String(data: json, encoding: .utf8) ?? "?")
      let chunks = json.chunk(into: 176)
      let numItems: UInt8 = UInt8(chunks.count)
      let result = chunks.enumerated().map { (index, chunk) in
        Data([Cmd.Notif.rawValue, notifyId, numItems, UInt8(index)]) + chunk
      }
      notifyId &+= 1
      return result
    }
    public static func configData(directPush: Bool, durationS: UInt8) -> Data {
      let directPushByte: UInt8 = directPush ? 1 : 0
      return Data([Cmd.NotifConfig.rawValue, directPushByte, durationS])
    }
  }
  public struct Navigate {
    static var seqId: UInt8 = 0x00
    static func parseExampleImage(image: String) -> [Bool] {
      return image.parseHex().convertToBits()
    }
    public static func initData() -> Data {
      // Note saw also right before start:
      // Both: [0x39, 0x05, 0x00, 0x7C, 0x01]
      // Right: [0x50, 0x06, 0x00, 0x00, 0x01, 0x01]
      let part: [UInt8] = [0x00, seqId, 0x00, 0x01]
      let data = Data([Cmd.Navigate.rawValue, UInt8(part.count + 2)] + part)
      seqId &+= 1
      return data
    }
    struct DirectionTurn {
      static let StraightDot: UInt8 = 0x01
      static let Straight: UInt8 = 0x02
      static let Right: UInt8 = 0x03
      static let Left: UInt8 = 0x04
      static let SlightRight: UInt8 = 0x05
      static let SlightLeft: UInt8 = 0x06
      static let StrongRight: UInt8 = 0x07
      static let StrongLeft: UInt8 = 0x08
      static let UTurnLeft: UInt8 = 0x09
      static let UTurnRight: UInt8 = 0x0A
      static let Merge: UInt8 = 0x0B
      static let RightLaneRightStrongAtRoundabout: UInt8 = 0x0C
      static let LeftLaneRightStrongAtRoundabout: UInt8 = 0x0D
      static let RightLaneRightAtRoundabout: UInt8 = 0x0E
      static let LeftLaneRightAtRoundabout: UInt8 = 0x0F
      static let RightLaneSlightRightAtRoundabout: UInt8 = 0x10
      static let LeftLaneSlightRightAtRoundabout: UInt8 = 0x11
      static let RightLaneStraightAtRoundabout: UInt8 = 0x12
      static let LeftLaneStraightAtRoundabout: UInt8 = 0x13
      static let RightLaneSlightLeftAtRoundabout: UInt8 = 0x14
      static let LeftLaneSlightLeftAtRoundabout: UInt8 = 0x15
      static let RightLaneLeftAtRoundabout: UInt8 = 0x16
      static let LeftLaneLeftAtRoundabout: UInt8 = 0x17
      static let RightLaneStrongLeftAtRoundabout: UInt8 = 0x18
      static let LeftLaneStrongLeftAtRoundabout: UInt8 = 0x19
      static let RightLaneUTurnAtRoundabout: UInt8 = 0x1A
      static let LeftLaneUTurnAtRoundabout: UInt8 = 0x1B
      static let RightLaneEnterRoundabout: UInt8 = 0x1C
      static let LeftLaneEnterRoundabout: UInt8 = 0x1D
      static let RightLaneExitRoundabout: UInt8 = 0x1E
      static let LeftLaneExitRoundabout: UInt8 = 0x1F
      static let RightOfframp: UInt8 = 0x20
      static let LeftOfframp: UInt8 = 0x21
      static let SlightRightAtFork: UInt8 = 0x22
      static let SlightLeftAtFork: UInt8 = 0x23
    }
    public static func directionsData(
      totalDuration: String, totalDistance: String, direction: String, distance: String,
      speed: String, x: [UInt8], y: UInt8
    ) -> Data {
      let unknown1: UInt8 = 0x01
      let totalDurationData: [UInt8] = totalDuration.uint8()
      let totalDistanceData: [UInt8] = totalDistance.uint8()
      let directionData: [UInt8] = direction.uint8()
      let distanceData: [UInt8] = distance.uint8()
      let speedData: [UInt8] = speed.uint8()

      let part0: [UInt8] = [null, seqId, unknown1, DirectionTurn.Straight] + x + [y, null]
      let part: [UInt8] =
        part0 + totalDurationData + nullArr + totalDistanceData + nullArr
        + directionData + nullArr + distanceData + nullArr + speedData + nullArr
      let data = Data([Cmd.Navigate.rawValue, UInt8(part.count + 2)] + part)
      return data
    }
    public static func primaryImageData(image: [Bool], overlay: [Bool]) -> [Data] {
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
        return Data([Cmd.Navigate.rawValue, UInt8(part.count + 2)] + part)
      }
    }
    public static func secondaryImageData(image: [Bool], overlay: [Bool]) -> [Data] {
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
        return Data([Cmd.Navigate.rawValue, UInt8(part.count + 2)] + part)
      }
    }
    static var pollerSeqId: UInt8 = 0x01
    public static func pollerData() -> Data {
      let partType4: UInt8 = 0x04
      let part: [UInt8] = [null, seqId, partType4, pollerSeqId]
      seqId &+= 1
      pollerSeqId &+= 1
      let data = Data([Cmd.Navigate.rawValue, UInt8(part.count + 2)] + part)
      return data
    }
    public static func endData() -> Data {
      let partType5: UInt8 = 0x05
      let part: [UInt8] = [null, seqId, partType5, 0x01]
      seqId &+= 1
      return Data([Cmd.Navigate.rawValue, UInt8(part.count + 2)] + part)
    }
  }
}
let deviceListeners: [Cmd: Listener] = [
  Cmd.AddNotif: { (peripheral, data, side, store) in
    guard let name = peripheral.name else { return }
    // 0x04ca
    logFailure(code: data[1], type: "add notif", name: name, data: data)
  },
  Cmd.Navigate: { (peripheral, data, side, store) in
    // response to navigation requests
    // mainVm?.glassesAppState = .Navigation
  },
  Cmd.Mic: { (peripheral, data, side, store) in
    let resp = Device.Mic.respData(data: data)
    log("mic action success: \(resp.isSuccess), enabled: \(resp.enable)")
  },
  Cmd.MicData: { (peripheral, data, side, store) in
    // let effectiveData = data.subdata(in: 2..<data.count)
    // let pcmConverter = PcmConverter()
    // let pcmData = pcmConverter.decode(effectiveData)

    // let inputData = pcmData as Data
    // mainVm?.connectionManager.speechRecognizer?.appendPcmData(inputData)
  },
  Cmd.Crc: { (peripheral, data, side, store) in
    if Device.Bmp.crcResp(data: data) {
      log("CRC check failed", data.hex)
    } else {
      log("CRC success")
    }
  },
  Cmd.Notes: { (peripheral, data, side, store) in
    // response to note update
    // Only the data[1] and data[3] changes, reflecting the original message (packet length and sequence number)
    // 1E10 003E 0301 0001 0000
    // 0x1e06001c01
    // log("0x1E: \(name) \(data.hex)")
  },
  Cmd.Bmp: { (peripheral, data, side, store) in
  },
  Cmd.BmpDone: { (peripheral, data, side, store) in
    guard let name = peripheral.name else { return }
    log("bmp done \(name), isSuccess: \(data[1] == 0xC9)")
    store.set(atom: glassesAppStateAtom, value: .Bmp)
  },
  Cmd.Notif: { (peripheral, data, side, store) in
    guard let name = peripheral.name else { return }
    let isSuccess = data[1] == 0xC9 || data[1] == 0xCB
    log("notif \(name), isSuccess: \(isSuccess), \(data.hex)")
  },
  Cmd.Heartbeat: { (peripheral, data, side, store) in
    // log("got heartbeat", data.hex)
  },
  Cmd.NotifConfig: { (peripheral, data, side, store) in
    guard let name = peripheral.name else { return }
    logFailure(code: data[1], type: "notif config", name: name, data: data)
  },
  Cmd.Ping: { (peripheral, data, side, store) in
    log("ping", data.hex)
  },
  Cmd.Text: { (peripheral, data, side, store) in
    // 0x4ec90001
    store.set(atom: glassesAppStateAtom, value: .Text)
  },
  Cmd.Teleprompter: { (peripheral, data, side, store) in
    // log("todo", data.hex)
  },
  Cmd.Exit: { (peripheral, data, side, store) in
    // ack exit
    // 0x18c9
    store.set(atom: glassesAppStateAtom, value: nil)
  },
  Cmd.Device: { (peripheral, data, side, store) in
    guard let name = peripheral.name else { return }
    let cmd = DeviceCmd(rawValue: data[1])
    switch cmd {
    case .SingleTap:
      log("single tap!", name)
    case .DoubleTap:
      log("double tap!", name)
    case .TripleTapSilent:
      log("silent mode on", name)
    case .TripleTapNormal:
      log("not silent mode", name)
    case .LookUp:
      log("look up", name, data.hex)

    // let text = "Looked up!"
    // guard let textData = G1Cmd.Text.data(text: text) else { break }
    // manager.transmitBoth(textData)
    case .LookDown:
      log("look down", name, data.hex)
    // let text = "Looked down!"
    // guard let textData = G1Cmd.Text.data(text: text) else { break }
    // manager.transmitBoth(textData)
    case .DashShown:
      log("dash shown", name, data.hex)
      store.set(atom: glassesAppStateAtom, value: .Dash)
    case .DashHide:
      log("dash hide", name, data.hex)
      store.set(atom: glassesAppStateAtom) { value in value == .Dash ? nil : value }
    case .CaseOpen:
      log("case open", data.hex)
      store.set(atom: glassesStateAtom, value: .CaseOpen)
    case .CaseClose:
      log("case close", data.hex)
      store.set(atom: glassesStateAtom, value: .CaseClosed)
    case .CaseCharging:
      log("case is charging: \(data[2])")
      store.set(atom: caseChargingAtom, value: data[2] == 1)
      // 0xf50e01
      break
    case .CaseBattery:
      log("case battery: \(data[2])")
      store.set(atom: caseBatteryAtom, value: Int(data[2]))
      // 0xf50f46
      break
    case .WearOn:
      log("wear on: \(name) \(data.hex)")
      store.set(atom: glassesStateAtom, value: .Wearing)
      // mainVm?.connectionManager.sendWearMessage()
      // 0xf506
      break
    case .WearOff:
      log("wear off: \(name) \(data.hex)")
      // wear off is also not in case
      store.set(atom: glassesStateAtom, value: .Off)
      // 0xf507
      break
    case .Charging:
      // 0xf50901
      store.set(atom: chargingAtom, value: data[2] == 1)
      break
    case .none:
      switch data[1] {
      case 0x00:
        break
      case 0x0A:
        // 0xf50a64
        break
      case 0x11:
        // L only, after Ping
        // 0xf511
        break
      case 0x12:
        // R Only
        // 0xf51206
        // 0xf5120c
        break
      default:
        log("unknown device command: \(name) \(data[1]) \(data.hex)")
        break
      }
    }
  },
]

public enum DeviceCmd: UInt8 {
  case SingleTap = 0x01
  case DoubleTap = 0x00
  case TripleTapSilent = 0x04
  case TripleTapNormal = 0x05
  case LookUp = 0x02
  case LookDown = 0x03
  case DashShown = 0x1E
  case DashHide = 0x1F
  case CaseOpen = 0x08
  case CaseClose = 0x0B
  case CaseCharging = 0x0E
  case CaseBattery = 0x0F
  case WearOn = 0x06
  case WearOff = 0x07
  case Charging = 0x09
}

enum GlassesAppState {
  case Text
  case Navigation
  case Dash
  case Bmp
}
let glassesAppStateAtom = PrimitiveAtom<GlassesAppState?>(nil)
public let chargingAtom = PrimitiveAtom(false)
public let caseBatteryAtom = PrimitiveAtom<Int?>(nil)
let caseChargingAtom = PrimitiveAtom(false)

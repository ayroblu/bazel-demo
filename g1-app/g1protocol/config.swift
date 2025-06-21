import jotai
import utils
import Foundation

struct Config {
  static func brightnessData(brightness: UInt8, auto: Bool) -> Data {
    let brightness: UInt8 = brightness > 63 ? 63 : brightness
    return Data([Cmd.Brightness.rawValue, brightness, auto ? 1 : 0])
  }
  static func silentModeData(enabled: Bool) -> Data {
    return Data([Cmd.SilentMode.rawValue, enabled ? 0x0C : 0x0A, 0x00])
  }
  static func wearDetectionData(enabled: Bool) -> Data {
    return Data([Cmd.WearDetection.rawValue, enabled ? 0x01 : 0x00])
  }
  enum DashModeConfig: UInt8 {
    case WeatherTime = 0x01
    case Calendar = 0x03
    case Layout = 0x06
    case Map = 0x07
  }
  static private var dashModeSeq: UInt8 = 0x00
  static private func dashModeGeneralData(_ config: DashModeConfig, _ data: [UInt8]) -> Data {
    let data: [UInt8] = [null, dashModeSeq, config.rawValue] + data
    dashModeSeq &+= 1
    let length: UInt8 = UInt8(data.count + 2)
    return Data([Cmd.DashMode.rawValue, length] + data)
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
    return dashModeGeneralData(
      DashModeConfig.Layout,
      [mode.rawValue, mode == DashMode.Minimal ? null : subMode.rawValue])
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
    return dashModeGeneralData(
      DashModeConfig.WeatherTime,
      epochTime32 + epochTime64 + [weatherIcon.rawValue, temp, fahrenheit, twelveHour])
  }
  static func headTiltData(angle: UInt8) -> Data? {
    guard angle >= 0 && angle <= 60 else { return nil }
    return Data([Cmd.HeadTilt.rawValue, UInt8(angle), 0x01])
  }
  enum HeadsUpConfig: UInt8 {
    case dashboard = 0x00
    case none = 0x02
  }
  static func headsUpConfig(_ config: HeadsUpConfig) -> Data {
    return Data([Cmd.HeadsUpConfig.rawValue, 0x06, null, null, 0x03, config.rawValue])
  }
  static func getHeadsUpConfig() -> Data {
    return Data([Cmd.HeadsUpConfig.rawValue, 0x06, null, null, 0x04, null])
  }
  static func dashData(isShow: Bool, vertical: UInt8, distance: UInt8) -> Data? {
    let cmd: UInt8 = 0x02
    let show: UInt8 = isShow ? 0x01 : 0x00
    guard vertical >= 1 && vertical <= 0x08 else { return nil }
    // distance is 1-5m in 0.5m increments
    guard distance >= 1 && distance <= 0x09 else { return nil }
    return Data([
      Cmd.DashConfig.rawValue, 0x08, 0x00, 0x01,
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
      0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x03, 0x01,
    ]
    let eventData: [UInt8] =
      fixedData + [UInt8(0x01), nameLength] + nameData + [UInt8(0x02), timeLength] + timeData
      + [UInt8(0x03), locationLength] + locationData
    return dashModeGeneralData(DashModeConfig.Calendar, eventData)
  }
  static private func mapDataParts(_ bytes: [UInt8]) -> [Data] {
    let maxLength = 182
    let chunks = bytes.chunk(into: maxLength)
    let packetCount: UInt8 = UInt8(chunks.count)
    return chunks.enumerated().map { (index, chunk) in
      let packetNum: UInt8 = UInt8(index + 1)
      return dashModeGeneralData(
        DashModeConfig.Map, [packetCount, null, packetNum, null] + chunk)
    }
  }
  static func mapData(image: [Bool], overlay: [Bool]) -> [Data] {
    let mapSomething: UInt8 = 0x04
    let signalParts = mapDataParts([null, null, mapSomething, null])
    // ((0xbd-9)*0x1c-3)*16/2=40296
    // image is 138 x 292 probably
    let imageBytes: [UInt8] = (image + overlay).toBytes().runLengthEncode()
    let mainParts = mapDataParts([null, mapSomething, UInt8(0x02)] + imageBytes)
    // 132 bytes of something I'm not sure what
    let finalParts = mapDataParts([null, mapSomething, UInt8(0x03)] + [UInt8(0x01)])
    return signalParts + mainParts + finalParts
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
        return Data([Cmd.Notes.rawValue, totalLength] + noteData)
      } else {
        let noteData: [UInt8] = [
          0x00, noteId, 0x03, 0x01, 0x00, 0x01, 0x00, noteIdx, 0x00,
          0x01, 0x00, 0x01, 0x00, 0x00,
        ]
        let totalLength: UInt8 = UInt8(noteData.count + 2)
        return Data([Cmd.Notes.rawValue, totalLength] + noteData)
      }
      // Checksum? Maybe just length
      // Send:    1E06 003F 0101
      // Receive: 1E06 0009 0100
    }
  }
}

let headsUpDashInternalAtom = PrimitiveAtom(true)
let headsUpDashAtom = WritableAtom<Bool, Bool, Void>(
  { getter in getter.get(atom: headsUpDashInternalAtom) },
  { (setter, value) in
    setter.set(atom: headsUpDashInternalAtom, value: value)
    let data = Config.headsUpConfig(value ? .dashboard : .none)
    bluetoothManager.transmitRight(data)
  })

let isBluetoothEnabledAtom = PrimitiveAtom(false)

let isConnectedAtom = PrimitiveAtom(false)

enum GlassesAppState {
  case Text
  case Navigation
  case Dash
  case Bmp
}
let glassesAppStateAtom = PrimitiveAtom<GlassesAppState?>(nil)

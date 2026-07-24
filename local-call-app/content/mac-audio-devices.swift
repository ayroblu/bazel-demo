#if os(macOS)
import CoreAudio
import Foundation
import Log

nonisolated private func getStringProperty(
  deviceID: AudioDeviceID, selector: AudioObjectPropertySelector
) -> String? {
  var address = AudioObjectPropertyAddress(
    mSelector: selector,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
  let value = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
  value.initialize(to: nil)
  defer {
    value.deinitialize(count: 1)
    value.deallocate()
  }
  var size = UInt32(MemoryLayout<CFString?>.size)
  let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, value)
  guard status == noErr, let value = value.pointee else { return nil }
  return value as String
}

nonisolated private func getInputChannelCount(deviceID: AudioDeviceID) -> Int {
  var address = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyStreamConfiguration,
    mScope: kAudioDevicePropertyScopeInput,
    mElement: kAudioObjectPropertyElementMain)
  var size: UInt32 = 0
  guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
    return 0
  }

  let bufferListPointer = UnsafeMutableRawPointer.allocate(
    byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
  defer { bufferListPointer.deallocate() }

  let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer)
  guard status == noErr else { return 0 }

  let bufferList = UnsafeMutableAudioBufferListPointer(
    bufferListPointer.assumingMemoryBound(to: AudioBufferList.self))
  return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
}

nonisolated private func getDefaultInputDeviceID() -> AudioDeviceID? {
  var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
  var deviceID = AudioDeviceID(0)
  var size = UInt32(MemoryLayout<AudioDeviceID>.size)
  let status = AudioObjectGetPropertyData(
    AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
  guard status == noErr, deviceID != 0 else { return nil }
  return deviceID
}

nonisolated private func getDeviceIDs() -> [AudioDeviceID] {
  var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
  var size: UInt32 = 0
  guard AudioObjectGetPropertyDataSize(
    AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
    return []
  }
  let count = Int(size) / MemoryLayout<AudioDeviceID>.size
  var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
  let status = AudioObjectGetPropertyData(
    AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)
  guard status == noErr else { return [] }
  return deviceIDs
}

nonisolated func logMacInputDevices() {
  let defaultInputID = getDefaultInputDeviceID()
  if let defaultInputID {
    log(
      "mac default input",
      getStringProperty(deviceID: defaultInputID, selector: kAudioObjectPropertyName) ?? "unknown",
      "uid",
      getStringProperty(deviceID: defaultInputID, selector: kAudioDevicePropertyDeviceUID) ?? "unknown",
      "channels",
      getInputChannelCount(deviceID: defaultInputID))
  } else {
    log("mac default input", "none")
  }

  for deviceID in getDeviceIDs() {
    let inputChannels = getInputChannelCount(deviceID: deviceID)
    guard inputChannels > 0 else { continue }
    let marker = deviceID == defaultInputID ? "default" : "available"
    log(
      "mac input device", marker,
      getStringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName) ?? "unknown",
      "uid",
      getStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) ?? "unknown",
      "channels",
      inputChannels)
  }
}
#else
nonisolated func logMacInputDevices() {}
#endif

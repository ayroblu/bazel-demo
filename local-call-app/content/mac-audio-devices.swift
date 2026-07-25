#if os(macOS)
import CoreAudio
import Log

nonisolated private func getInputProperty<T>(
  deviceID: AudioObjectID, selector: AudioObjectPropertySelector, initial: T
) -> T? {
  var address = AudioObjectPropertyAddress(
    mSelector: selector,
    mScope: selector == kAudioHardwarePropertyDefaultInputDevice
      ? kAudioObjectPropertyScopeGlobal : kAudioDevicePropertyScopeInput,
    mElement: kAudioObjectPropertyElementMain)
  var value = initial
  var size = UInt32(MemoryLayout<T>.size)
  guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
    return nil
  }
  return value
}

/// A muted or zero-volume input device delivers valid buffers of pure
/// silence with no error, so warn loudly since it looks like a working call.
nonisolated func warnIfMacInputMuted() {
  guard
    let deviceID = getInputProperty(
      deviceID: AudioObjectID(kAudioObjectSystemObject),
      selector: kAudioHardwarePropertyDefaultInputDevice, initial: AudioDeviceID(0)),
    deviceID != 0
  else {
    log("mac default input device not found")
    return
  }
  let volume = getInputProperty(
    deviceID: deviceID, selector: kAudioDevicePropertyVolumeScalar, initial: Float32(0))
  let muted = getInputProperty(
    deviceID: deviceID, selector: kAudioDevicePropertyMute, initial: UInt32(0))
  if muted == 1 || volume == 0 {
    log("mac default input is muted or has zero volume, no audio will be captured")
  }
}
#else
nonisolated func warnIfMacInputMuted() {}
#endif

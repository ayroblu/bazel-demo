#if os(macOS)
import CoreAudio
import Log

nonisolated struct MacAudioDevice: Identifiable, Hashable {
  let id: AudioDeviceID
  let name: String
}

/// Thin wrappers over the CoreAudio C property API for enumerating devices,
/// reading the system defaults, and observing hardware changes.
nonisolated enum MacAudio {
  /// Read a fixed-size trivial (non-object) property value.
  static func getProperty<T>(
    object: AudioObjectID, selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T
  ) -> T? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutablePointer(to: &value) { pointer in
      AudioObjectGetPropertyData(object, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer))
    }
    guard status == noErr else {
      return nil
    }
    return value
  }

  /// The device the system currently routes to when nothing is pinned.
  static func defaultDeviceID(input: Bool) -> AudioDeviceID? {
    let id = getProperty(
      object: AudioObjectID(kAudioObjectSystemObject),
      selector: input
        ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
      initial: AudioDeviceID(0))
    guard let id, id != 0 else { return nil }
    return id
  }

  static func devices(input: Bool) -> [MacAudioDevice] {
    allDeviceIDs()
      .filter { hasStreams($0, input: input) }
      .map { MacAudioDevice(id: $0, name: name(of: $0)) }
  }

  /// Observe a hardware property on the system object (device list, default
  /// input/output device). The listener is never removed; callers are
  /// expected to live for the app's lifetime.
  static func listen(
    selector: AudioObjectPropertySelector,
    onChange: @escaping @Sendable @MainActor () -> Void
  ) {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectAddPropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
    ) { _, _ in
      Task { @MainActor in
        onChange()
      }
    }
    if status != noErr {
      log("failed to add core audio listener", selector, status)
    }
  }

  private static func allDeviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    let system = AudioObjectID(kAudioObjectSystemObject)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
      return []
    }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else {
      return []
    }
    return ids
  }

  private static func hasStreams(_ deviceID: AudioDeviceID, input: Bool) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
  }

  private static func name(of deviceID: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &value) { pointer in
      AudioObjectGetPropertyData(
        deviceID, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer))
    }
    guard status == noErr, let value else { return "Device \(deviceID)" }
    return value.takeRetainedValue() as String
  }
}

/// A muted or zero-volume input device delivers valid buffers of pure
/// silence with no error, so warn loudly since it looks like a working call.
nonisolated func warnIfMacInputMuted(deviceID: AudioDeviceID) {
  let volume = MacAudio.getProperty(
    object: deviceID, selector: kAudioDevicePropertyVolumeScalar,
    scope: kAudioDevicePropertyScopeInput, initial: Float32(0))
  let muted = MacAudio.getProperty(
    object: deviceID, selector: kAudioDevicePropertyMute,
    scope: kAudioDevicePropertyScopeInput, initial: UInt32(0))
  if muted == 1 || volume == 0 {
    log("mac input device is muted or has zero volume, no audio will be captured")
  }
}
#endif

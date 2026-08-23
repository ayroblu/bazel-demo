#if os(macOS)
import CoreAudio
import Log

/// Follows the system default input/output devices unless the user pins a
/// specific one. Picking the device that currently *is* the system default
/// clears the pin, so the call keeps following future default changes
/// (e.g. AirPods auto-switching) again.
class AudioRouteController: ObservableObject {
  @Published var inputOptions: [AudioOption] = []
  @Published var outputOptions: [AudioOption] = []
  @Published var currentInputID: String?
  @Published var currentOutputID: String?

  // nil = follow the system default.
  private var selectedInputID: AudioDeviceID?
  private var selectedOutputID: AudioDeviceID?
  private var defaultInputID: AudioDeviceID?
  private var defaultOutputID: AudioDeviceID?

  /// Called with the pinned devices (nil = follow default) whenever the
  /// effective devices may have changed.
  var onDevicesChanged: ((AudioDeviceID?, AudioDeviceID?) -> Void)?

  init() {
    guard !isRunningInPreview else { return }
    refresh()
    for selector in [
      kAudioHardwarePropertyDevices,
      kAudioHardwarePropertyDefaultInputDevice,
      kAudioHardwarePropertyDefaultOutputDevice,
    ] {
      MacAudio.listen(selector: selector) { [weak self] in
        self?.handleHardwareChange()
      }
    }
  }

  func activate() throws {
    refresh()
  }

  func deactivate() {}

  func selectInput(id: String?) {
    if isRunningInPreview {
      currentInputID = id
      return
    }
    guard let id, let deviceID = AudioDeviceID(id) else { return }
    selectedInputID = deviceID == defaultInputID ? nil : deviceID
    log("selected input", deviceID, "pinned", selectedInputID != nil)
    refresh()
    notify()
  }

  func selectOutput(id: String?) {
    if isRunningInPreview {
      currentOutputID = id
      return
    }
    guard let id, let deviceID = AudioDeviceID(id) else { return }
    selectedOutputID = deviceID == defaultOutputID ? nil : deviceID
    log("selected output", deviceID, "pinned", selectedOutputID != nil)
    refresh()
    notify()
  }

  private func handleHardwareChange() {
    refresh()
    notify()
  }

  func refresh() {
    guard !isRunningInPreview else { return }
    let inputs = MacAudio.devices(input: true)
    let outputs = MacAudio.devices(input: false)
    defaultInputID = MacAudio.defaultDeviceID(input: true)
    defaultOutputID = MacAudio.defaultDeviceID(input: false)
    // A pinned device that disappeared falls back to following the default.
    if let selected = selectedInputID, !inputs.contains(where: { $0.id == selected }) {
      log("pinned input device disappeared, following default")
      selectedInputID = nil
    }
    if let selected = selectedOutputID, !outputs.contains(where: { $0.id == selected }) {
      log("pinned output device disappeared, following default")
      selectedOutputID = nil
    }
    inputOptions = inputs.map { option(for: $0, defaultID: defaultInputID) }
    outputOptions = outputs.map { option(for: $0, defaultID: defaultOutputID) }
    currentInputID = (selectedInputID ?? defaultInputID).map { String($0) }
    currentOutputID = (selectedOutputID ?? defaultOutputID).map { String($0) }
    log(
      "audio devices", "default in", defaultInputID ?? 0, "default out", defaultOutputID ?? 0,
      "pinned in", selectedInputID ?? 0, "pinned out", selectedOutputID ?? 0)
  }

  private func option(for device: MacAudioDevice, defaultID: AudioDeviceID?) -> AudioOption {
    AudioOption(
      id: String(device.id),
      name: device.id == defaultID ? "\(device.name) (system default)" : device.name)
  }

  private func notify() {
    onDevicesChanged?(selectedInputID, selectedOutputID)
  }
}
#endif

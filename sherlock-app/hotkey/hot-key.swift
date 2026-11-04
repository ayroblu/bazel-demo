import Carbon.HIToolbox

public final class HotKey {
  private let action: () -> Void
  private let id: UInt32
  private var hotKeyRef: EventHotKeyRef?
  private var handlerRef: EventHandlerRef?

  public init(action: @escaping () -> Void) {
    self.action = action
    nextId += 1
    id = nextId
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(), handleHotKey, 1, &eventType,
      Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
  }

  public func register(_ shortcut: Shortcut) -> Bool {
    unregister()
    let hotKeyId = EventHotKeyID(signature: signature, id: id)
    return RegisterEventHotKey(
      shortcut.keyCode, shortcut.carbonModifiers, hotKeyId, GetApplicationEventTarget(), 0,
      &hotKeyRef) == noErr
  }

  public func unregister() {
    guard let hotKeyRef else { return }
    UnregisterEventHotKey(hotKeyRef)
    self.hotKeyRef = nil
  }

  fileprivate func handle(_ hotKeyId: EventHotKeyID) -> Bool {
    guard hotKeyId.signature == signature, hotKeyId.id == id else { return false }
    action()
    return true
  }
}

private var nextId: UInt32 = 0

private let signature = OSType(0x5348_4C4B)

private nonisolated func handleHotKey(
  _ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let userData, let event else { return OSStatus(eventNotHandledErr) }
  var hotKeyId = EventHotKeyID()
  GetEventParameter(
    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyId)
  let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
  let handled = MainActor.assumeIsolated { hotKey.handle(hotKeyId) }
  return handled ? noErr : OSStatus(eventNotHandledErr)
}

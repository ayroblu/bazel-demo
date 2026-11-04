import AppKit
import Carbon.HIToolbox
import Synchronization
import clipboard

public final class SnippetExpander {
  private let store: SnippetStore
  private let watcher = KeystrokeWatcher()

  public init(store: SnippetStore) {
    self.store = store
    watcher.onMatch = { [weak self] keyword in
      Task { @MainActor in self?.expand(keyword) }
    }
  }

  public func configure(enabled: Bool) {
    watcher.setKeywords(store.items.map(\.keyword).filter { !$0.isEmpty })
    if !(enabled && canPaste && watcher.start()) {
      watcher.stop()
    }
  }

  private func expand(_ keyword: String) {
    guard let snippet = store.items.first(where: { $0.keyword == keyword }) else { return }
    for _ in keyword {
      postKey(kVK_Delete)
    }
    paste(store.render(snippet))
  }
}

private nonisolated final class KeystrokeWatcher: @unchecked Sendable {
  var onMatch: @Sendable (String) -> Void = { _ in }
  private let keywords = Mutex<(set: Set<String>, maxLength: Int)>(([], 0))
  private var buffer: [Character] = []
  private var tap: CFMachPort?

  func setKeywords(_ newKeywords: [String]) {
    keywords.withLock { $0 = (Set(newKeywords), newKeywords.map(\.count).max() ?? 0) }
  }

  func start() -> Bool {
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: true)
      return true
    }
    let mask = [CGEventType.keyDown, .leftMouseDown, .rightMouseDown].reduce(CGEventMask(0)) {
      $0 | (1 << $1.rawValue)
    }
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: mask, callback: handleTapEvent,
        userInfo: Unmanaged.passUnretained(self).toOpaque())
    else { return false }
    self.tap = tap
    Thread { [self] in
      CFRunLoopAddSource(
        CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, self.tap, 0), .commonModes)
      CFRunLoopRun()
    }.start()
    return true
  }

  func stop() {
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: false)
    }
  }

  fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      if let tap {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
    case .keyDown:
      handleKeyDown(event)
    default:
      buffer.removeAll()
    }
  }

  private func handleKeyDown(_ event: CGEvent) {
    guard event.getIntegerValueField(.eventSourceUserData) != syntheticEventMarker else { return }
    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    if keyCode == kVK_Delete {
      _ = buffer.popLast()
      return
    }
    guard event.flags.isDisjoint(with: [.maskCommand, .maskControl]),
      !bufferResettingKeys.contains(keyCode)
    else {
      buffer.removeAll()
      return
    }
    var length = 0
    var characters = [UniChar](repeating: 0, count: 4)
    event.keyboardGetUnicodeString(
      maxStringLength: characters.count, actualStringLength: &length, unicodeString: &characters)
    buffer.append(contentsOf: String(utf16CodeUnits: characters, count: length))
    let (set, maxLength) = keywords.withLock { $0 }
    if buffer.count > max(maxLength, 1) * 2 {
      buffer.removeFirst(buffer.count - maxLength)
    }
    for length in stride(from: min(maxLength, buffer.count), through: 1, by: -1) {
      let candidate = String(buffer.suffix(length))
      if set.contains(candidate) {
        buffer.removeAll()
        onMatch(candidate)
        return
      }
    }
  }
}

private nonisolated func handleTapEvent(
  _ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
  _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  if let userInfo {
    Unmanaged<KeystrokeWatcher>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
  }
  return Unmanaged.passUnretained(event)
}

private nonisolated let bufferResettingKeys: Set<Int> = [
  kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_Escape, kVK_LeftArrow, kVK_RightArrow,
  kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete,
]

import AppKit
import ApplicationServices
import Carbon.HIToolbox

public nonisolated let syntheticEventMarker: Int64 = 0x5348_4C4B

public var canPaste: Bool { AXIsProcessTrusted() }

public func requestPastePermission() {
  let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
  _ = AXIsProcessTrustedWithOptions(options)
}

public func paste(_ text: String) {
  let pasteboard = NSPasteboard.general
  guard canPaste else {
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    return
  }
  let previous = snapshot(pasteboard)
  pasteboard.clearContents()
  pasteboard.declareTypes([.string, transientType], owner: nil)
  pasteboard.setString(text, forType: .string)
  Task {
    try? await Task.sleep(for: .milliseconds(80))
    postKey(kVK_ANSI_V, flags: .maskCommand)
    try? await Task.sleep(for: .milliseconds(400))
    pasteboard.clearContents()
    pasteboard.writeObjects(previous)
  }
}

public func pasteClipboard() {
  guard canPaste else { return }
  Task {
    try? await Task.sleep(for: .milliseconds(80))
    postKey(kVK_ANSI_V, flags: .maskCommand)
  }
}

public func postKey(_ keyCode: Int, flags: CGEventFlags = []) {
  let source = CGEventSource(stateID: .combinedSessionState)
  for isDown in [true, false] {
    let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: isDown)
    event?.flags = flags
    event?.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
    event?.post(tap: .cghidEventTap)
  }
}

private func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
  (pasteboard.pasteboardItems ?? []).map { item in
    let copy = NSPasteboardItem()
    for type in item.types {
      if let data = item.data(forType: type) {
        copy.setData(data, forType: type)
      }
    }
    return copy
  }
}

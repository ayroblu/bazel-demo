import AppKit
import Carbon.HIToolbox
import SwiftUI
import hotkey

struct ShortcutRecorder: View {
  @Binding var shortcut: Shortcut
  @Binding var pausesHotKeys: Bool
  let standard: Shortcut
  @State private var isRecording = false
  @State private var monitor = KeyDownMonitor()

  var body: some View {
    HStack {
      if shortcut != standard, !isRecording {
        Button("Reset") { shortcut = standard }
      }
      Button {
        setRecording(!isRecording)
      } label: {
        Text(isRecording ? "Type shortcut…" : shortcut.description).frame(minWidth: 110)
      }
    }
    .onDisappear { setRecording(false) }
  }

  private func setRecording(_ recording: Bool) {
    isRecording = recording
    pausesHotKeys = recording
    if recording {
      monitor.start(record)
    } else {
      monitor.stop()
    }
  }

  private func record(_ event: NSEvent) {
    if event.keyCode == kVK_Escape {
      setRecording(false)
    } else if let recorded = Shortcut(event: event) {
      shortcut = recorded
      setRecording(false)
    }
  }
}

private final class KeyDownMonitor {
  private var token: Any?

  func start(_ handler: @escaping (NSEvent) -> Void) {
    stop()
    token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handler(event)
      return nil
    }
  }

  func stop() {
    guard let token else { return }
    NSEvent.removeMonitor(token)
    self.token = nil
  }
}

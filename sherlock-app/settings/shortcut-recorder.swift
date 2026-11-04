import AppKit
import Carbon.HIToolbox
import SwiftUI
import hotkey

struct ShortcutRecorder: View {
  let id: String
  @Binding var shortcut: Shortcut
  @Binding var recording: String?
  let standard: Shortcut
  @State private var monitor = KeyDownMonitor()

  var body: some View {
    HStack {
      if shortcut != standard, !isRecording {
        Button("Reset") { shortcut = standard }
      }
      Button {
        recording = isRecording ? nil : id
      } label: {
        Text(isRecording ? "Type shortcut…" : shortcut.description).frame(minWidth: 110)
      }
    }
    .onChange(of: isRecording) { _, isRecording in
      if isRecording {
        monitor.start(record)
      } else {
        monitor.stop()
      }
    }
    .onDisappear {
      if isRecording {
        recording = nil
      }
    }
  }

  private var isRecording: Bool { recording == id }

  private func record(_ event: NSEvent) {
    if event.keyCode == kVK_Escape {
      recording = nil
    } else if let recorded = Shortcut(event: event) {
      shortcut = recorded
      recording = nil
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

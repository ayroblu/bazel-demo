import AppKit
import ServiceManagement
import SwiftUI
import clipboard
import hotkey
import preferences
import search
import snippets

public final class SettingsWindowController {
  private let preferences: Preferences
  private let clipboard: ClipboardHistory
  private let snippets: SnippetStore
  private var window: NSWindow?

  public init(preferences: Preferences, clipboard: ClipboardHistory, snippets: SnippetStore) {
    self.preferences = preferences
    self.clipboard = clipboard
    self.snippets = snippets
  }

  public var isVisible: Bool { window?.isVisible ?? false }

  public func show() {
    let window = self.window ?? makeWindow()
    self.window = window
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(
      at: Bundle.main.bundleURL, configuration: configuration, completionHandler: nil)
  }

  private func makeWindow() -> NSWindow {
    let view = SettingsView(preferences: preferences, clipboard: clipboard, snippets: snippets)
    let controller = NSHostingController(rootView: view)
    controller.sizingOptions = []
    let window = NSWindow(contentViewController: controller)
    window.title = "Sherlock Settings"
    window.styleMask = [.titled, .closable, .resizable]
    window.isReleasedWhenClosed = false
    window.contentMinSize = NSSize(width: settingsWidth, height: 300)
    window.contentMaxSize = NSSize(width: settingsWidth, height: .greatestFiniteMagnitude)
    let screenHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 80
    window.setContentSize(NSSize(width: settingsWidth, height: min(640, screenHeight)))
    window.center()
    return window
  }
}

private struct SettingsView: View {
  @Bindable var preferences: Preferences
  let clipboard: ClipboardHistory
  let snippets: SnippetStore
  @State private var usesSystemShortcut = false
  @State private var runningLaunchers: [String] = []
  @State private var canSearchAllFiles = true
  @State private var canPasteIntoApps = true
  @State private var snippetCount = 0
  @State private var snippetMessage: String?
  @State private var configFolderError: String?
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
  @State private var launchAtLoginError: String?

  var body: some View {
    Form {
      Section("Hotkeys") {
        LabeledContent("Show Sherlock") {
          ShortcutRecorder(
            shortcut: $preferences.shortcut, pausesHotKeys: $preferences.isRecordingShortcut,
            standard: .standard)
        }
        if !preferences.hotKeyRegistered {
          warning(
            "Sherlock couldn't register \(preferences.shortcut.description). Choose another shortcut.",
            color: .red)
        }
        ForEach(runningLaunchers, id: \.self) { name in
          warning(
            "\(name) is running. If it also uses \(preferences.shortcut.description), change its hotkey or quit it."
          )
        }
        if usesSystemShortcut {
          warning(
            "macOS also uses \(preferences.shortcut.description), for example for Spotlight. Turn it off in System Settings > Keyboard > Keyboard Shortcuts.",
            button: "Open Keyboard Shortcuts…", url: keyboardSettingsURL)
        }
        LabeledContent("Clipboard History") {
          ShortcutRecorder(
            shortcut: $preferences.clipboardShortcut,
            pausesHotKeys: $preferences.isRecordingShortcut,
            standard: Preferences.standardClipboardShortcut)
        }
        if !preferences.clipboardHotKeyRegistered {
          warning(
            "Sherlock couldn't register \(preferences.clipboardShortcut.description). Choose another shortcut.",
            color: .red)
        }
      }
      Section("Search") {
        Toggle("Search files with Spotlight", isOn: $preferences.searchFiles)
        if !canSearchAllFiles {
          warning(
            "macOS hides Desktop, Documents, Downloads and Safari bookmarks and history from Sherlock until you turn on Sherlock in Full Disk Access.",
            button: "Open Full Disk Access…", url: fullDiskAccessURL)
        }
      }
      Section("Clipboard") {
        Toggle("Keep clipboard history", isOn: $preferences.clipboardHistory)
        LabeledContent("Keyword") {
          KeywordField(keyword: $preferences.clipboardKeyword)
        }
        Picker("Keep items for", selection: $preferences.clipboardRetentionDays) {
          Text("1 day").tag(1)
          Text("7 days").tag(7)
          Text("30 days").tag(30)
        }
        .disabled(!preferences.clipboardHistory)
        Toggle(isOn: $preferences.autoPaste) {
          Text("Paste into the front app")
          Text("Applies to clipboard history and snippets. When off, ↩ copies the item so you can paste it with ⌘V.")
        }
        Button("Clear Clipboard History") { clipboard.clear() }
      }
      Section("Snippets") {
        LabeledContent("\(snippetCount) \(snippetCount == 1 ? "snippet" : "snippets")") {
          HStack {
            Button("Import Alfred Snippets…", action: importAlfredSnippets)
            Button("Edit…", action: openSnippetsFile)
          }
        }
        if let snippetMessage {
          Text(snippetMessage).foregroundStyle(.secondary)
        }
        LabeledContent("Keyword") {
          KeywordField(keyword: $preferences.snippetKeyword)
        }
        Toggle("Expand snippet keywords as you type", isOn: $preferences.expandSnippets)
      }
      if !canPasteIntoApps {
        Section("Permissions") {
          warning(
            "Sherlock needs Accessibility access to paste clipboard items and snippets into apps, and to expand snippets as you type. Until then it copies them to the clipboard.",
            button: "Grant Accessibility Access…", action: requestPastePermission)
        }
      }
      Section("Config") {
        LabeledContent("Config folder") {
          Text((preferences.configFolder.path as NSString).abbreviatingWithTildeInPath)
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        HStack {
          Button("Choose…", action: chooseConfigFolder)
          Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([preferences.configFolder])
          }
          if preferences.configFolder != Preferences.standardConfigFolder {
            Button("Reset to Default") { moveConfig(to: Preferences.standardConfigFolder) }
          }
        }
        Text(
          "Holds settings.yaml and snippets.yaml. Changing the folder moves them there, unless it already has its own, which Sherlock then uses."
        )
        .foregroundStyle(.secondary)
        if let configFolderError {
          Text(configFolderError).foregroundStyle(.red)
        }
      }
      Section {
        Toggle("Show menu bar icon", isOn: $preferences.showMenuBarIcon)
        Toggle("Launch at login", isOn: $launchAtLogin)
        if let launchAtLoginError {
          Text(launchAtLoginError).foregroundStyle(.red)
        }
        Button("Quit Sherlock") { NSApp.terminate(nil) }
      }
    }
    .formStyle(.grouped)
    .frame(width: settingsWidth)
    .onAppear(perform: refreshStatus)
    .onChange(of: preferences.shortcut, refreshStatus)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) {
      _ in refreshStatus()
    }
    .onChange(of: launchAtLogin) { _, enabled in
      do {
        if enabled {
          try SMAppService.mainApp.register()
        } else {
          try SMAppService.mainApp.unregister()
        }
        launchAtLoginError = nil
      } catch {
        launchAtLoginError = error.localizedDescription
      }
    }
  }

  private func refreshStatus() {
    usesSystemShortcut = isSystemShortcut(preferences.shortcut)
    canSearchAllFiles = hasFullDiskAccess()
    canPasteIntoApps = canPaste
    snippets.reloadIfChanged()
    snippetCount = snippets.snippets.count
    runningLaunchers = otherLaunchers.compactMap { bundleId, name in
      NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty ? nil : name
    }
  }

  private func importAlfredSnippets() {
    let panel = NSOpenPanel()
    panel.message = "Choose an Alfred.alfredpreferences bundle or its snippets folder"
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.treatsFilePackagesAsDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let added = try snippets.importAlfredSnippets(from: url)
      snippetMessage = "Imported \(added) new snippets."
    } catch {
      snippetMessage = "Couldn't import snippets: \(error.localizedDescription)"
    }
    refreshStatus()
  }

  private func chooseConfigFolder() {
    let panel = NSOpenPanel()
    panel.message = "Choose where Sherlock keeps its settings and snippets"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.directoryURL = preferences.configFolder
    guard panel.runModal() == .OK, let url = panel.url else { return }
    moveConfig(to: url)
  }

  private func moveConfig(to folder: URL) {
    do {
      try snippets.moveFolder(to: folder)
      try preferences.moveConfigFolder(to: folder)
      configFolderError = nil
    } catch {
      configFolderError = "Couldn't move config: \(error.localizedDescription)"
    }
    refreshStatus()
  }

  private func openSnippetsFile() {
    let url = snippets.fileURL
    if !FileManager.default.fileExists(atPath: url.path) {
      try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? "[]\n".write(to: url, atomically: true, encoding: .utf8)
    }
    NSWorkspace.shared.open(url)
  }

  private func warning(
    _ text: String, color: Color = .orange, button: String? = nil, url: URL? = nil,
    action: (() -> Void)? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(text).foregroundStyle(color)
      if let button {
        Button(button) {
          if let url {
            NSWorkspace.shared.open(url)
          }
          action?()
        }
      }
    }
  }
}

private let settingsWidth: CGFloat = 500

private let keyboardSettingsURL = URL(
  string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!

private let fullDiskAccessURL = URL(
  string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

private struct KeywordField: View {
  @Binding var keyword: String
  @State private var draft = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    TextField("", text: $draft)
      .labelsHidden()
      .frame(width: 120)
      .multilineTextAlignment(.trailing)
      .focused($isFocused)
      .onAppear { draft = keyword }
      .onSubmit(commit)
      .onChange(of: isFocused) { _, focused in
        if !focused { commit() }
      }
  }

  private func commit() {
    let value = draft.trimmingCharacters(in: .whitespaces).lowercased()
    if !value.isEmpty, !value.contains(where: \.isWhitespace) {
      keyword = value
    }
    draft = keyword
  }
}

private let otherLaunchers = [
  ("com.raycast.macos", "Raycast"), ("com.runningwithcrayons.Alfred", "Alfred"),
]

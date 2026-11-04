import AppKit
import ServiceManagement
import SwiftUI
import bindings
import clipboard
import extensions
import hotkey
import preferences
import search
import snippets

public final class SettingsWindowController {
  private let preferences: Preferences
  private let clipboard: ClipboardHistory
  private let snippets: SnippetStore
  private let quickLinks: QuickLinkStore
  private let extensions: Extensions
  private let hotkeyStore: HotkeyStore
  private let hotkeyBindings: HotkeyBindings
  private var window: NSWindow?

  public init(
    preferences: Preferences, clipboard: ClipboardHistory, snippets: SnippetStore,
    quickLinks: QuickLinkStore, extensions: Extensions, hotkeyStore: HotkeyStore,
    hotkeyBindings: HotkeyBindings
  ) {
    self.preferences = preferences
    self.clipboard = clipboard
    self.snippets = snippets
    self.quickLinks = quickLinks
    self.extensions = extensions
    self.hotkeyStore = hotkeyStore
    self.hotkeyBindings = hotkeyBindings
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
    let view = SettingsView(
      preferences: preferences, clipboard: clipboard, snippets: snippets, quickLinks: quickLinks,
      extensions: extensions, hotkeyStore: hotkeyStore, hotkeyBindings: hotkeyBindings)
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
  let quickLinks: QuickLinkStore
  let extensions: Extensions
  let hotkeyStore: HotkeyStore
  let hotkeyBindings: HotkeyBindings
  @State private var usesSystemShortcut = false
  @State private var runningLaunchers: [String] = []
  @State private var canSearchAllFiles = true
  @State private var canPasteIntoApps = true
  @State private var snippetCount = 0
  @State private var quickLinkCount = 0
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
        ForEach(hotkeyBindings.statuses) { status in
          VStack(alignment: .leading, spacing: 4) {
            LabeledContent(status.target) {
              Text(status.shortcut)
            }
            if let error = status.error {
              Text(error).foregroundStyle(.red)
            }
          }
        }
        LabeledContent("Hotkeys for apps, searches and AppleScript") {
          Button("Edit…") { openConfigFile(hotkeyStore.fileURL) }
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
          Button("Edit…") { openConfigFile(snippets.fileURL) }
        }
        LabeledContent("Keyword") {
          KeywordField(keyword: $preferences.snippetKeyword)
        }
        Toggle("Expand snippet keywords as you type", isOn: $preferences.expandSnippets)
      }
      Section("Quick Links") {
        LabeledContent("\(quickLinkCount) \(quickLinkCount == 1 ? "quick link" : "quick links")") {
          Button("Edit…") { openConfigFile(quickLinks.fileURL) }
        }
        Text(
          "Type a keyword and your search, like ‘npm react’, to open its URL with {query} replaced."
        )
        .foregroundStyle(.secondary)
      }
      Section("Extensions") {
        ForEach(extensions.summaries) { summary in
          LabeledContent(summary.name) {
            Text(statusText(summary.status)).foregroundStyle(statusColor(summary.status))
          }
        }
        Button("Open Extensions Folder") {
          try? FileManager.default.createDirectory(
            at: extensions.folderURL, withIntermediateDirectories: true)
          NSWorkspace.shared.open(extensions.folderURL)
        }
        Text(
          "Each folder with an extension.yaml is an extension. Its setup runs in a copy that it can write to; its commands then run in a sandbox that can only write to its data folder."
        )
        .foregroundStyle(.secondary)
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
          "Holds settings.yaml, snippets.yaml, quicklinks.yaml, hotkeys.yaml and extensions/. Edits apply as soon as you save. Changing the folder moves the files there, unless it already has its own, which Sherlock then uses."
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
    quickLinks.reloadIfChanged()
    quickLinkCount = quickLinks.links.count
    runningLaunchers = otherLaunchers.compactMap { bundleId, name in
      NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty ? nil : name
    }
  }

  private func statusText(_ status: ExtensionStatus) -> String {
    switch status {
    case .settingUp: "Setting up…"
    case .ready: "Ready"
    case .failed(let error): error
    }
  }

  private func statusColor(_ status: ExtensionStatus) -> Color {
    switch status {
    case .settingUp: .secondary
    case .ready: .green
    case .failed: .red
    }
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
      try quickLinks.moveFolder(to: folder)
      try hotkeyStore.moveFolder(to: folder)
      try extensions.moveFolder(to: folder)
      try preferences.moveConfigFolder(to: folder)
      configFolderError = nil
    } catch {
      configFolderError = "Couldn't move config: \(error.localizedDescription)"
    }
    refreshStatus()
  }

  private func openConfigFile(_ url: URL) {
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

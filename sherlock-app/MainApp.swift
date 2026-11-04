import AppKit
import Observation
import bar
import clipboard
import extensions
import hotkey
import preferences
import search
import settings
import snippets

@main
struct SherlockApp {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let preferences = Preferences()
  private let clipboard = ClipboardHistory()
  private lazy var snippets = SnippetStore(folder: preferences.configFolder)
  private lazy var quickLinks = QuickLinkStore(folder: preferences.configFolder)
  private lazy var extensions = Extensions(configFolder: preferences.configFolder)
  private lazy var configWatcher = FolderWatcher { [weak self] in self?.reloadConfig() }
  private lazy var expander = SnippetExpander(store: snippets)
  private lazy var search = SearchController(
    preferences: preferences, clipboard: clipboard, snippets: snippets, quickLinks: quickLinks,
    extensions: extensions)
  private lazy var settings = SettingsWindowController(
    preferences: preferences, clipboard: clipboard, snippets: snippets, quickLinks: quickLinks,
    extensions: extensions)
  private lazy var hotKey = HotKey { [weak self] in self?.search.toggle() }
  private lazy var clipboardHotKey = HotKey { [weak self] in self?.showClipboard() }
  private var statusItem: NSStatusItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = makeMainMenu()
    search.onOpenSettings = { [weak self] in self?.settings.show() }
    updateHotKey()
    updateStatusItem()
    if !preferences.hotKeyRegistered || isSystemShortcut(preferences.shortcut)
      || (preferences.searchFiles && !hasFullDiskAccess())
    {
      settings.show()
    }
    Task {
      for await _ in Observations({
        (
          self.preferences.shortcut, self.preferences.clipboardShortcut,
          self.preferences.isRecordingShortcut
        )
      }) {
        updateHotKey()
      }
    }
    Task {
      for await _ in Observations({ self.preferences.showMenuBarIcon }) {
        updateStatusItem()
      }
    }
    Task {
      for await (enabled, days) in Observations({
        (self.preferences.clipboardHistory, self.preferences.clipboardRetentionDays)
      }) {
        clipboard.configure(enabled: enabled, retentionDays: days)
      }
    }
    Task {
      for await _ in Observations({ self.preferences.expandSnippets }) {
        updateSnippetExpansion()
      }
    }
    snippets.onChange = { [weak self] in self?.updateSnippetExpansion() }
    Task {
      for await folder in Observations({ self.preferences.configFolder }) {
        configWatcher.watch(folder)
      }
    }
    DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(1))
        self?.updateSnippetExpansion()
      }
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !settings.isVisible {
      search.show()
    }
    return false
  }

  @objc private func showSearch() {
    search.show()
  }

  @objc private func showClipboard() {
    search.show(text: preferences.clipboardKeyword + " ")
  }

  @objc private func openSettings() {
    settings.show()
  }

  private func updateHotKey() {
    if preferences.isRecordingShortcut {
      hotKey.unregister()
      clipboardHotKey.unregister()
    } else {
      preferences.hotKeyRegistered = hotKey.register(preferences.shortcut)
      preferences.clipboardHotKeyRegistered = clipboardHotKey.register(
        preferences.clipboardShortcut)
    }
  }

  private func reloadConfig() {
    preferences.reloadIfChanged()
    snippets.reloadIfChanged()
    quickLinks.reloadIfChanged()
    extensions.reload()
  }

  private func updateSnippetExpansion() {
    expander.configure(enabled: preferences.expandSnippets)
  }

  private func updateStatusItem() {
    if preferences.showMenuBarIcon, statusItem == nil {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      item.button?.image = NSImage(
        systemSymbolName: "magnifyingglass", accessibilityDescription: "Sherlock")
      item.menu = makeStatusMenu()
      statusItem = item
    } else if !preferences.showMenuBarIcon, let statusItem {
      NSStatusBar.system.removeStatusItem(statusItem)
      self.statusItem = nil
    }
  }

  private func makeStatusMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(withTitle: "Open Sherlock", action: #selector(showSearch), keyEquivalent: "")
      .target = self
    menu.addItem(
      withTitle: "Clipboard History", action: #selector(showClipboard), keyEquivalent: ""
    ).target = self
    menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
      .target = self
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit Sherlock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    return menu
  }

  private func makeMainMenu() -> NSMenu {
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
      .target = self
    appMenu.addItem(
      withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    let mainMenu = NSMenu()
    for submenu in [appMenu, editMenu] {
      let item = NSMenuItem()
      item.submenu = submenu
      mainMenu.addItem(item)
    }
    return mainMenu
  }
}

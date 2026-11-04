import AppKit

nonisolated enum SystemCommand: String, CaseIterable, Sendable {
  case lock
  case sleep
  case restart
  case shutDown
  case logOut
  case emptyTrash
  case eject

  @MainActor
  func run() {
    switch self {
    case .lock: lockScreen()
    case .sleep: _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/pmset"), arguments: ["sleepnow"])
    case .restart: sendToLoginWindow("rrst", failure: "Couldn't restart")
    case .shutDown: sendToLoginWindow("rsdn", failure: "Couldn't shut down")
    case .logOut: sendToLoginWindow("logo", failure: "Couldn't log out")
    case .emptyTrash: confirmAndEmptyTrash()
    case .eject: ejectAll()
    }
  }

  fileprivate var details: (names: [String], subtitle: String, symbol: String) {
    switch self {
    case .lock: (["Lock", "Lock Screen"], "Lock the screen", "lock.fill")
    case .sleep: (["Sleep"], "Put your Mac to sleep", "moon.fill")
    case .restart: (["Restart", "Reboot"], "Restart your Mac", "arrow.clockwise")
    case .shutDown: (["Shut Down", "Shutdown", "Power Off"], "Shut down your Mac", "power")
    case .logOut:
      (["Log Out", "Logout", "Sign Out"], "Log out of your account", "rectangle.portrait.and.arrow.right")
    case .emptyTrash: (["Empty Trash"], "Erase the items in the Trash", "trash.fill")
    case .eject: (["Eject All", "Eject"], "Eject all external disks and disk images", "eject.fill")
    }
  }
}

nonisolated func commandCandidates() -> [Candidate] {
  SystemCommand.allCases.map { command in
    let details = command.details
    let item = ResultItem(
      id: "command:" + command.rawValue, title: details.names[0], subtitle: details.subtitle,
      icon: .symbol(details.symbol), action: .command(command))
    return Candidate(item: item, names: details.names.flatMap { searchNames($0) })
  }
}

func showAlert(_ message: String, details: String) {
  let alert = NSAlert()
  alert.messageText = message
  alert.informativeText = details
  _ = runInFront(alert)
}

private func lockScreen() {
  let login = dlopen(
    "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY)
  guard let symbol = dlsym(login, "SACLockScreenImmediate") else {
    showAlert("Couldn't lock the screen", details: "This version of macOS doesn't support it.")
    return
  }
  typealias LockScreen = @convention(c) () -> Int32
  _ = unsafeBitCast(symbol, to: LockScreen.self)()
}

private func sendToLoginWindow(_ eventId: String, failure: String) {
  let event = NSAppleEventDescriptor(
    eventClass: AEEventClass(kCoreEventClass),
    eventID: eventId.utf8.reduce(0) { $0 << 8 | AEEventID($1) },
    targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow"),
    returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
  do {
    try event.sendEvent(options: [.noReply], timeout: 5)
  } catch {
    showAlert(failure, details: error.localizedDescription)
  }
}

private func confirmAndEmptyTrash() {
  let alert = NSAlert()
  alert.messageText = "Empty the Trash?"
  alert.informativeText = "The items in the Trash will be erased permanently."
  alert.addButton(withTitle: "Empty Trash")
  alert.addButton(withTitle: "Cancel")
  guard runInFront(alert) == .alertFirstButtonReturn else { return }
  var error: NSDictionary?
  NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
  if let error {
    showAlert(
      "Couldn't empty the Trash", details: error[NSAppleScript.errorMessage] as? String ?? "")
  }
}

private func ejectAll() {
  let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey]
  let volumes =
    FileManager.default.mountedVolumeURLs(
      includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
  for volume in volumes {
    let values = try? volume.resourceValues(forKeys: Set(keys))
    guard values?.volumeIsEjectable == true || values?.volumeIsRemovable == true else { continue }
    do {
      try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
    } catch {
      showAlert("Couldn't eject \(volume.lastPathComponent)", details: error.localizedDescription)
    }
  }
}

private func runInFront(_ alert: NSAlert) -> NSApplication.ModalResponse {
  NSApp.activate()
  alert.window.level = .floating
  return alert.runModal()
}

import Foundation
import clipboard
import extensions
import snippets

public nonisolated struct ResultItem: Sendable {
  public enum Icon: Hashable, Sendable {
    case file(String)
    case symbol(String)
    case image(String)
    case favicon(Data, badge: String)
    case text(String)
  }

  public enum Preview: Sendable {
    case clipboard(ClipboardEntry)
    case snippet(Snippet)
    case file(URL)
  }

  public let id: String
  public let title: String
  public let subtitle: String
  public let icon: Icon
  let action: Action

  public var revealPath: String? {
    guard case .open(let url) = action, url.isFileURL else { return nil }
    return url.path
  }

  public var isMessage: Bool {
    guard case .none = action else { return false }
    return true
  }

  public var autocompletion: String? {
    guard case .autocomplete(let text) = action else { return nil }
    return text
  }

  public var question: String? {
    guard case .ask(let question) = action else { return nil }
    return question
  }

  public var preview: Preview? {
    switch action {
    case .clipboard(let entry): .clipboard(entry)
    case .snippet(let snippet): .snippet(snippet)
    case .open(let url) where url.isFileURL && url.pathExtension != "app": .file(url)
    default: nil
    }
  }
}

nonisolated enum Action: Sendable {
  case open(URL)
  case copy(String)
  case paste(String)
  case clipboard(ClipboardEntry)
  case snippet(Snippet)
  case autocomplete(String)
  case ask(String)
  case command(SystemCommand)
  case extensionAction(ExtensionCommand, String)
  case none
}

nonisolated func fileItem(path: String, title: String) -> ResultItem {
  ResultItem(
    id: path, title: title, subtitle: displayPath(path), icon: .file(path),
    action: .open(URL(fileURLWithPath: path)))
}

private nonisolated func displayPath(_ path: String) -> String {
  if path.hasPrefix(iCloudDrivePath) {
    return "iCloud Drive" + path.dropFirst(iCloudDrivePath.count)
  }
  return (path as NSString).abbreviatingWithTildeInPath
}

private nonisolated let iCloudDrivePath =
  NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs"

import AppKit
import preferences

public nonisolated struct Snippet: Codable, Sendable, Equatable {
  public var name: String
  public var keyword: String
  public var text: String
}

public typealias SnippetStore = ConfigList<Snippet>

extension ConfigList where Item == Snippet {
  public convenience init(snippetsIn folder: URL) {
    self.init(folder: folder, name: "snippets.yaml")
  }

  public func render(_ snippet: Snippet) -> String {
    render(snippet.text, depth: 0)
  }

  private func render(_ text: String, depth: Int) -> String {
    text.replacing(placeholderPattern) { match in
      let name = String(match.output.1)
      switch name {
      case "clipboard":
        return NSPasteboard.general.string(forType: .string) ?? ""
      case "date":
        return Date().formatted(date: .abbreviated, time: .omitted)
      case "time":
        return Date().formatted(date: .omitted, time: .shortened)
      case "datetime":
        return Date().formatted(date: .abbreviated, time: .shortened)
      case "random:UUID":
        return UUID().uuidString
      default:
        if name.hasPrefix("date:") {
          let formatter = DateFormatter()
          formatter.dateFormat = String(name.dropFirst("date:".count))
          return formatter.string(from: Date())
        }
        let keyword = name.dropFirst("snippet:".count)
        guard depth < 3, let nested = items.first(where: { $0.keyword == keyword }) else {
          return String(match.output.0)
        }
        return render(nested.text, depth: depth + 1)
      }
    }
  }
}

private let placeholderPattern = /\{(clipboard|date|time|datetime|random:UUID|date:[^}]*|snippet:[^}]*)\}/

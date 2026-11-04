import AppKit
import preferences

public nonisolated struct Snippet: Codable, Sendable, Equatable {
  public var name: String
  public var keyword: String
  public var text: String
  public var collection: String
}

public final class SnippetStore {
  public var onChange: () -> Void = {}
  public private(set) var snippets: [Snippet] = []
  public private(set) var version = 0
  private let file: ConfigFile<[Snippet]>

  public init(folder: URL) {
    file = ConfigFile(folder: folder, name: "snippets.yaml")
    load()
  }

  public var fileURL: URL { file.url }

  public func moveFolder(to folder: URL) throws {
    try file.move(to: folder)
    load()
  }

  public func reloadIfChanged() {
    guard file.hasChanged else { return }
    load()
  }

  public func importAlfredSnippets(from folder: URL) throws -> Int {
    let imported = try readAlfredSnippets(in: folder)
    let added = imported.filter { !snippets.contains($0) }
    try file.save(snippets + added)
    load()
    return added.count
  }

  public func render(_ snippet: Snippet) -> String {
    render(snippet.text, depth: 0)
  }

  private func load() {
    guard let loaded = file.load() ?? (file.exists ? nil : []) else { return }
    snippets = loaded
    version += 1
    onChange()
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
        guard name.hasPrefix("snippet:"), depth < 3,
          let nested = snippets.first(where: { $0.keyword == keyword })
        else { return String(match.output.0) }
        return render(nested.text, depth: depth + 1)
      }
    }
  }
}

private let placeholderPattern = /\{(clipboard|date|time|datetime|random:UUID|date:[^}]*|snippet:[^}]*)\}/

private func readAlfredSnippets(in folder: URL) throws -> [Snippet] {
  let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
    .compactMap { $0 as? URL }.filter { $0.pathExtension == "json" } ?? []
  return files.compactMap { file in
    guard let data = try? Data(contentsOf: file),
      let wrapper = try? JSONDecoder().decode(AlfredSnippetFile.self, from: data)
    else { return nil }
    let collectionFolder = file.deletingLastPathComponent()
    let info = NSDictionary(contentsOf: collectionFolder.appending(path: "info.plist"))
    let prefix = info?["snippetkeywordprefix"] as? String ?? ""
    let suffix = info?["snippetkeywordsuffix"] as? String ?? ""
    let snippet = wrapper.alfredsnippet
    let keyword = snippet.keyword ?? ""
    let fullKeyword =
      keyword.isEmpty
      ? "" : (keyword.hasPrefix(prefix) ? "" : prefix) + keyword
        + (keyword.hasSuffix(suffix) ? "" : suffix)
    return Snippet(
      name: snippet.name ?? keyword, keyword: fullKeyword, text: snippet.snippet,
      collection: collectionFolder.lastPathComponent)
  }
}

private struct AlfredSnippetFile: Decodable {
  struct Body: Decodable {
    let snippet: String
    let name: String?
    let keyword: String?
  }

  let alfredsnippet: Body
}

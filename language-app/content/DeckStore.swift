import CryptoKit
import Foundation
import Observation

public enum DeckStoreError: LocalizedError, Equatable {
  case emptyName
  case duplicateName(String)
  case unreadableFile(String)
  case writeFailed(String)

  public var errorDescription: String? {
    switch self {
    case .emptyName: "A deck needs a name."
    case let .duplicateName(name): "A deck called \(name) already exists."
    case let .unreadableFile(name): "\(name) could not be read as a CSV deck."
    case let .writeFailed(name): "\(name) could not be saved."
    }
  }
}

/// Decks live as CSV files in the app's documents directory so they can be edited.
/// Bundled decks are copied in on first launch, and refreshed later while they stay unedited.
@MainActor
@Observable
public final class DeckStore {
  public private(set) var decks: [Deck] = []
  public private(set) var errors: [String] = []

  private let directory: URL
  private let defaults: UserDefaults
  private let fileManager = FileManager.default
  private let seedKey = "language-app.seeded-deck-digests.v1"

  public init(
    directory: URL = DeckStore.defaultDirectory,
    bundledDecks: [URL] = DeckStore.bundledDeckURLs(),
    defaults: UserDefaults = .standard
  ) {
    self.directory = directory
    self.defaults = defaults
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      errors.append("The decks folder could not be created.")
    }
    seed(from: bundledDecks)
    reload()
  }

  public static var defaultDirectory: URL {
    URL.documentsDirectory.appending(path: "decks", directoryHint: .isDirectory)
  }

  public static func bundledDeckURLs(in bundle: Bundle = .main) -> [URL] {
    let nested = bundle.urls(forResourcesWithExtension: "csv", subdirectory: "decks") ?? []
    let root = bundle.urls(forResourcesWithExtension: "csv", subdirectory: nil) ?? []
    return nested + root
  }

  public func deck(id: String) -> Deck? {
    decks.first { $0.id == id }
  }

  /// Writes an edited deck back to its file. The deck keeps its name, so its progress key holds.
  public func replace(_ deck: Deck) throws {
    try write(deck, to: url(forName: deck.name))
    if let index = decks.firstIndex(where: { $0.id == deck.id }) {
      decks[index] = deck
    } else {
      insertSorted(deck)
    }
  }

  public func createDeck(
    name: String,
    languageCode: String,
    answerColumnName: String
  ) throws -> Deck {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw DeckStoreError.emptyName }
    let destination = url(forName: trimmed)
    guard !fileManager.fileExists(atPath: destination.path) else {
      throw DeckStoreError.duplicateName(trimmed)
    }
    let deck = Deck(
      name: trimmed,
      languageCode: languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      answerColumnName: answerColumnName.trimmingCharacters(in: .whitespacesAndNewlines),
      cards: []
    )
    try write(deck, to: destination)
    insertSorted(deck)
    return deck
  }

  /// Copies an external CSV into the deck folder, numbering the file when the name is taken.
  public func importDeck(from source: URL) throws -> Deck {
    let filename = source.deletingPathExtension().lastPathComponent
    guard let data = try? Data(contentsOf: source),
      let parsed = try? CSVDeckLoader.load(name: displayName(for: filename), data: data)
    else {
      throw DeckStoreError.unreadableFile(source.lastPathComponent)
    }
    let slug = availableSlug(for: slug(from: filename))
    let deck = Deck(
      name: displayName(for: slug),
      languageCode: parsed.languageCode,
      answerColumnName: parsed.answerColumnName,
      cards: parsed.cards
    )
    try write(deck, to: directory.appending(path: "\(slug).csv"))
    insertSorted(deck)
    return deck
  }

  public func delete(_ deck: Deck) throws {
    let target = url(forName: deck.name)
    do {
      if fileManager.fileExists(atPath: target.path) {
        try fileManager.removeItem(at: target)
      }
    } catch {
      throw DeckStoreError.writeFailed(deck.name)
    }
    decks.removeAll { $0.id == deck.id }
    StudyStore.removeStoredData(deckId: deck.id, from: defaults)
    var digests = seededDigests()
    digests.removeValue(forKey: target.lastPathComponent)
    saveSeededDigests(digests)
  }

  // MARK: - Files

  /// The recorded digest stays as the bundled text that was copied in, never the text being
  /// written. That is what lets the next launch tell an edited deck from an untouched copy.
  private func write(_ deck: Deck, to destination: URL) throws {
    do {
      try Data(CSVDeckWriter.encode(deck).utf8).write(to: destination, options: .atomic)
    } catch {
      throw DeckStoreError.writeFailed(deck.name)
    }
  }

  private func reload() {
    decks = []
    let urls =
      (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
      .filter { $0.pathExtension.lowercased() == "csv" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

    for url in urls {
      let name = displayName(for: url.deletingPathExtension().lastPathComponent)
      do {
        decks.append(try CSVDeckLoader.load(name: name, data: Data(contentsOf: url)))
      } catch {
        errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
      }
    }
  }

  private func seed(from bundledDecks: [URL]) {
    let sources = Dictionary(
      bundledDecks.map { ($0.lastPathComponent, $0) },
      uniquingKeysWith: { first, _ in first }
    )

    var digests = seededDigests()
    for (filename, source) in sources.sorted(by: { $0.key < $1.key }) {
      guard let bundled = try? String(contentsOf: source, encoding: .utf8) else { continue }
      let destination = directory.appending(path: filename)
      let bundledDigest = digest(of: bundled)
      let existing = try? String(contentsOf: destination, encoding: .utf8)

      if let existing {
        // Only refresh a copy the reader has not edited.
        guard digests[filename] == digest(of: existing), digests[filename] != bundledDigest else {
          continue
        }
      }
      do {
        try Data(bundled.utf8).write(to: destination, options: .atomic)
        digests[filename] = bundledDigest
      } catch {
        errors.append("\(filename) could not be copied into the decks folder.")
      }
    }
    saveSeededDigests(digests)
  }

  private func insertSorted(_ deck: Deck) {
    decks.append(deck)
    decks.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
  }

  private func url(forName name: String) -> URL {
    directory.appending(path: "\(slug(from: name)).csv")
  }

  private func availableSlug(for base: String) -> String {
    var candidate = base
    var suffix = 2
    while fileManager.fileExists(atPath: directory.appending(path: "\(candidate).csv").path) {
      candidate = "\(base)-\(suffix)"
      suffix += 1
    }
    return candidate
  }

  private func slug(from name: String) -> String {
    let lowered = name.lowercased()
    let allowed = lowered.map { character -> Character in
      character.isLetter || character.isNumber ? character : "-"
    }
    let collapsed = String(allowed).split(separator: "-", omittingEmptySubsequences: true)
    let slug = collapsed.joined(separator: "-")
    return slug.isEmpty ? "deck" : slug
  }

  private func displayName(for filename: String) -> String {
    filename
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "_", with: " ")
      .localizedCapitalized
  }

  private func digest(of text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func seededDigests() -> [String: String] {
    defaults.dictionary(forKey: seedKey) as? [String: String] ?? [:]
  }

  private func saveSeededDigests(_ digests: [String: String]) {
    defaults.set(digests, forKey: seedKey)
  }
}

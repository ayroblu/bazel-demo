import Foundation
import Observation

@MainActor
@Observable
public final class DeckLibrary {
  public private(set) var decks: [Deck] = []
  public private(set) var errors: [String] = []

  public init(bundle: Bundle = .main) {
    loadBundledDecks(from: bundle)
  }

  public init(decks: [Deck]) {
    self.decks = decks
  }

  private func loadBundledDecks(from bundle: Bundle) {
    let nestedURLs = bundle.urls(forResourcesWithExtension: "csv", subdirectory: "decks") ?? []
    let rootURLs = bundle.urls(forResourcesWithExtension: "csv", subdirectory: nil) ?? []
    let urls = Dictionary(
      (nestedURLs + rootURLs).map { ($0.lastPathComponent, $0) },
      uniquingKeysWith: { first, _ in first }
    ).values

    for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
      do {
        let filename = url.deletingPathExtension().lastPathComponent
        let name = filename
          .replacingOccurrences(of: "-", with: " ")
          .replacingOccurrences(of: "_", with: " ")
          .localizedCapitalized
        decks.append(try CSVDeckLoader.load(name: name, data: Data(contentsOf: url)))
      } catch {
        errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
      }
    }

    if decks.isEmpty, errors.isEmpty {
      errors.append("No bundled CSV decks were found.")
    }
  }
}

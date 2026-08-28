import Log
import SwiftUI

public struct ContentView: View {
  @State private var decks = DeckStore()
  @State private var importing = false
  @State private var creating = false
  @State private var errorMessage: String?
  @State private var deleting: Deck?

  public init() {}

  private var emptyStateMessage: String {
    decks.errors.isEmpty
      ? "No decks yet. Use the plus button to add one."
      : decks.errors.joined(separator: "\n")
  }

  public var body: some View {
    NavigationStack {
      Group {
        if decks.decks.isEmpty {
          ContentUnavailableView(
            "No decks",
            systemImage: "rectangle.stack.badge.minus",
            description: Text(emptyStateMessage)
          )
        } else {
          List(decks.decks) { deck in
            DeckLink(deck: deck, decks: decks, deleting: $deleting)
          }
          .confirmationDialog(
            deleting.map { "Delete \($0.name)?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
          ) { deck in
            Button("Delete deck", role: .destructive) {
              tryLog("deleteDeck") { try decks.delete(deck) }
            }
            Button("Cancel", role: .cancel) {}
          } message: { deck in
            Text("The deck file and its \(deck.cards.count) cards are removed from this device.")
          }
        }
      }
      .navigationTitle("Decks")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Menu {
            Button("Upload a CSV deck", systemImage: "square.and.arrow.down") {
              importing = true
            }
            Button("Create a deck by hand", systemImage: "square.and.pencil") {
              creating = true
            }
          } label: {
            Label("Add deck", systemImage: "plus")
          }
        }
      }
      .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText]) { result in
        switch result {
        case let .success(url):
          do {
            _ = try decks.importDeck(from: url)
          } catch {
            errorMessage = error.localizedDescription
          }
        case let .failure(error):
          errorMessage = error.localizedDescription
        }
      }
      .sheet(isPresented: $creating) {
        NewDeckView(decks: decks)
      }
      .alert("Deck not added", isPresented: .constant(errorMessage != nil)) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }
}

private struct DeckLink: View {
  let deck: Deck
  let decks: DeckStore
  @Binding var deleting: Deck?
  @State private var store: StudyStore
  @State private var confirmingReset = false
  @State private var inspecting = false
  @State private var browsing = false

  init(deck: Deck, decks: DeckStore, deleting: Binding<Deck?>) {
    self.deck = deck
    self.decks = decks
    _deleting = deleting
    _store = State(initialValue: StudyStore(deck: deck))
  }

  var body: some View {
    NavigationLink {
      StudyDeckView(deck: deck, store: store)
    } label: {
      DeckRow(deck: deck, store: store)
    }
    .contextMenu {
      Button("Browse deck", systemImage: "book") { browsing = true }
      Button("Inspect deck", systemImage: "list.bullet.rectangle") { inspecting = true }
      Button("Reset progress", systemImage: "arrow.counterclockwise", role: .destructive) {
        confirmingReset = true
      }
      Button("Delete deck", systemImage: "trash", role: .destructive) {
        deleting = deck
      }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button("Delete", systemImage: "trash", role: .destructive) {
        tryLog("deleteDeck") { try decks.delete(deck) }
      }
    }
    // The deck file can change while this row is on screen, so the study queue follows it.
    .onChange(of: deck) { _, updated in store.updateDeck(updated) }
    .sheet(isPresented: $inspecting) {
      DeckInspectorView(deck: deck, decks: decks, store: store)
    }
    .sheet(isPresented: $browsing) {
      BrowseDeckView(
        deck: deck,
        speechRate: store.speechRate,
        questionRepeats: store.browseQuestionRepeats
      )
    }
    .confirmationDialog(
      "Reset progress for \(deck.name)?",
      isPresented: $confirmingReset,
      titleVisibility: .visible
    ) {
      Button("Reset progress", role: .destructive) { store.resetProgress() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Every card in this deck becomes new again. This cannot be undone.")
    }
  }
}

private struct DeckRow: View {
  let deck: Deck
  let store: StudyStore

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: "rectangle.stack.fill")
        .font(.title2)
        .foregroundStyle(.tint)
        .frame(width: 36, height: 36)
      VStack(alignment: .leading, spacing: 3) {
        Text(deck.name)
          .font(.headline)
        QueueCountsView(counts: store.counts)
          .font(.subheadline)
        Text("\(deck.cards.count) cards · \(languageName(deck.languageCode))")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 5)
  }

  private func languageName(_ code: String) -> String {
    Locale.current.localizedString(forLanguageCode: code) ?? code
  }
}

private struct NewDeckView: View {
  let decks: DeckStore
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var languageCode = "ja"
  @State private var answerColumnName = "en"
  @State private var errorMessage: String?

  private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    NavigationStack {
      Form {
        Section("Deck") {
          TextField("Name", text: $name)
        }
        Section {
          TextField("Prompt language code", text: $languageCode)
            .autocorrectionDisabled()
          TextField("Answer column name", text: $answerColumnName)
            .autocorrectionDisabled()
        } header: {
          Text("Columns")
        } footer: {
          Text(
            "The prompt language code drives speech, such as ja or es. Add cards from the deck's Inspect deck menu."
          )
        }
        if let errorMessage {
          Text(errorMessage)
            .foregroundStyle(.red)
        }
      }
      .navigationTitle("New deck")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") { create() }
            .disabled(trimmedName.isEmpty || languageCode.isEmpty || answerColumnName.isEmpty)
        }
      }
    }
    .frame(minWidth: 360, minHeight: 300)
  }

  private func create() {
    do {
      _ = try decks.createDeck(
        name: trimmedName,
        languageCode: languageCode,
        answerColumnName: answerColumnName
      )
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

import SwiftUI

struct DeckInspectorView: View {
  let deck: Deck
  let decks: DeckStore
  let store: StudyStore
  @Environment(\.dismiss) private var dismiss
  @State private var editing: DeckCard?
  @State private var adding = false
  @State private var errorMessage: String?

  private var editor: DeckEditor {
    DeckEditor(deck: deck) { store.isStudied($0) }
  }

  var body: some View {
    NavigationStack {
      Group {
        if deck.cards.isEmpty {
          ContentUnavailableView {
            Label("No cards yet", systemImage: "rectangle.stack.badge.plus")
          } description: {
            Text("Add cards by hand, or replace this deck with an uploaded CSV.")
          } actions: {
            Button("Add a card") { adding = true }
              .buttonStyle(.borderedProminent)
          }
        } else {
          cardList
        }
      }
      .navigationTitle(deck.name)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Add card", systemImage: "plus") { adding = true }
        }
        #if os(iOS)
          ToolbarItem(placement: .topBarLeading) { EditButton() }
        #endif
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(isPresented: $adding) {
        CardEditorView(languageCode: deck.languageCode, card: nil) { prompt, answer in
          add(prompt: prompt, answer: answer)
        }
      }
      .sheet(item: $editing) { card in
        CardEditorView(languageCode: deck.languageCode, card: card) { prompt, answer in
          update(card, prompt: prompt, answer: answer)
        }
      }
      .alert("Deck not saved", isPresented: .constant(errorMessage != nil)) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
    }
    .frame(minWidth: 420, minHeight: 420)
  }

  private var cardList: some View {
    List {
      Section {
        ForEach(Array(deck.cards.enumerated()), id: \.element.id) { index, card in
          row(index: index, card: card)
            .moveDisabled(store.isStudied(card))
            .deleteDisabled(store.isStudied(card))
        }
        .onMove(perform: move)
        .onDelete(perform: delete)
      } header: {
        Text("\(deck.cards.count) cards · \(editor.lockedCount) studied")
      } footer: {
        Text(
          "New cards are introduced from the top down. A card's schedule is tied to its text, so studied cards cannot be edited, moved or removed until you reset the deck's progress."
        )
      }
    }
  }

  private func row(index: Int, card: DeckCard) -> some View {
    let studied = store.isStudied(card)
    return Button {
      guard !studied else { return }
      editing = card
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text("\(index + 1)")
          .font(.caption)
          .monospacedDigit()
          .foregroundStyle(.tertiary)
          .frame(minWidth: 34, alignment: .trailing)
        VStack(alignment: .leading, spacing: 2) {
          Text(FuriganaParser.displayText(card.prompt))
            .font(.body)
          Text(card.answer)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        Spacer(minLength: 8)
        if studied {
          Image(systemName: "lock.fill")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .accessibilityLabel("Studied and locked")
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button("Edit card", systemImage: "pencil") { editing = card }
        .disabled(studied)
      Button("Move up", systemImage: "arrow.up") { shift(from: index, by: -1) }
        .disabled(studied || index == 0)
      Button("Move down", systemImage: "arrow.down") { shift(from: index, by: 1) }
        .disabled(studied || index == deck.cards.count - 1)
      Button("Remove card", systemImage: "trash", role: .destructive) {
        save { try editor.remove(at: IndexSet(integer: index)) }
      }
      .disabled(studied)
    }
  }

  // MARK: - Edits

  private func move(from source: IndexSet, to destination: Int) {
    save { try editor.move(from: source, to: destination) }
  }

  private func delete(at offsets: IndexSet) {
    save { try editor.remove(at: offsets) }
  }

  private func shift(from index: Int, by offset: Int) {
    save { try editor.shift(from: index, by: offset) }
  }

  private func add(prompt: String, answer: String) {
    save { try editor.append(prompt: prompt, answer: answer) }
  }

  private func update(_ card: DeckCard, prompt: String, answer: String) {
    save { try editor.replace(card, prompt: prompt, answer: answer) }
  }

  private func save(_ edit: () throws -> Deck) {
    do {
      let updated = try edit()
      try decks.replace(updated)
      store.updateDeck(updated)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct CardEditorView: View {
  let languageCode: String
  let card: DeckCard?
  let save: (String, String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var prompt: String
  @State private var answer: String

  init(languageCode: String, card: DeckCard?, save: @escaping (String, String) -> Void) {
    self.languageCode = languageCode
    self.card = card
    self.save = save
    _prompt = State(initialValue: card?.prompt ?? "")
    _answer = State(initialValue: card?.answer ?? "")
  }

  private var trimmedPrompt: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var trimmedAnswer: String { answer.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Prompt", text: $prompt, axis: .vertical)
        } header: {
          Text("Prompt (\(languageCode))")
        } footer: {
          Text("Add readings after Japanese words with brackets: 日本語[にほんご].")
        }

        Section("Answer") {
          TextField("Answer", text: $answer, axis: .vertical)
        }

        if !trimmedPrompt.isEmpty {
          Section("Preview") {
            FuriganaText(source: trimmedPrompt)
              .frame(maxWidth: .infinity)
            if Romaji.isSupported(languageCode: languageCode),
              let romaji = Romaji.transliterate(trimmedPrompt)
            {
              Text(romaji)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .navigationTitle(card == nil ? "New card" : "Edit card")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            save(trimmedPrompt, trimmedAnswer)
            dismiss()
          }
          .disabled(trimmedPrompt.isEmpty || trimmedAnswer.isEmpty)
        }
      }
    }
    .frame(minWidth: 380, minHeight: 360)
  }
}

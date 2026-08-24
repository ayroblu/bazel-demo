import AVFoundation
import SwiftUI

public struct ContentView: View {
  @State private var library = DeckLibrary()

  public init() {}

  public var body: some View {
    NavigationStack {
      Group {
        if library.decks.isEmpty {
          ContentUnavailableView(
            "No decks",
            systemImage: "rectangle.stack.badge.minus",
            description: Text(library.errors.joined(separator: "\n"))
          )
        } else {
          List(library.decks) { deck in
            DeckLink(deck: deck)
          }
        }
      }
      .navigationTitle("Decks")
    }
  }
}

private struct DeckLink: View {
  let deck: Deck
  @State private var store: StudyStore

  init(deck: Deck) {
    self.deck = deck
    _store = State(initialValue: StudyStore(deck: deck))
  }

  var body: some View {
    NavigationLink {
      StudyDeckView(deck: deck, store: store)
    } label: {
      DeckRow(deck: deck, store: store)
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
        Text("\(store.dueCards.count) due · \(deck.cards.count) cards · \(languageName(deck.languageCode))")
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

private struct StudyDeckView: View {
  let deck: Deck
  @Bindable var store: StudyStore
  private let speech = SpeechPlayer()
  @State private var showingSettings = false

  var body: some View {
    Group {
      if let card = store.currentCard {
        StudyCardView(card: card, store: store, speech: speech)
      } else {
        CompleteView(nextDueDate: store.nextDueDate)
      }
    }
    .navigationTitle(deck.name)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Settings", systemImage: "gearshape") { showingSettings = true }
      }
    }
    .sheet(isPresented: $showingSettings) {
      SettingsView(store: store)
    }
  }
}

private struct StudyCardView: View {
  let card: DeckCard
  @Bindable var store: StudyStore
  let speech: SpeechPlayer

  var body: some View {
    VStack(spacing: 24) {
      HStack {
        Label("\(store.dueCards.count) due", systemImage: "rectangle.stack")
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          speech.speak(card.prompt, languageCode: card.languageCode)
        } label: {
          Label("Listen", systemImage: "speaker.wave.2.fill")
        }
        .buttonStyle(.bordered)
      }

      Spacer(minLength: 8)
      FuriganaText(source: card.prompt)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(FuriganaParser.speechText(card.prompt))

      if store.showingAnswer {
        Divider()
        Text(card.answer)
          .font(.title3)
          .multilineTextAlignment(.center)
          .textSelection(.enabled)
        RatingButtons(store: store)
      } else {
        Button("Show answer") { store.revealAnswer() }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .keyboardShortcut(.space, modifiers: [])
      }
      Spacer(minLength: 8)
    }
    .padding()
    .frame(maxWidth: 720)
  }
}

private struct FuriganaText: View {
  let source: String

  var body: some View {
    HStack(alignment: .bottom, spacing: 0) {
      ForEach(Array(FuriganaParser.parse(source).enumerated()), id: \.offset) { _, segment in
        VStack(spacing: 1) {
          Text(segment.reading ?? " ")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(segment.text)
            .font(.system(size: 42, weight: .medium))
        }
      }
    }
    .multilineTextAlignment(.center)
  }
}

private struct RatingButtons: View {
  let store: StudyStore

  var body: some View {
    ViewThatFits {
      HStack(spacing: 10) { buttons }
      VStack(spacing: 10) { buttons }
    }
  }

  @ViewBuilder
  private var buttons: some View {
    ForEach(CardRating.allCases, id: \.rawValue) { rating in
      Button {
        store.grade(rating)
      } label: {
        VStack(spacing: 2) {
          Text(rating.title)
          Text(intervalLabel(store.previewInterval(for: rating)))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .tint(tint(for: rating))
    }
  }

  private func intervalLabel(_ days: Int) -> String {
    days == 1 ? "1 day" : "\(days) days"
  }

  private func tint(for rating: CardRating) -> Color {
    switch rating {
    case .again: .red
    case .hard: .orange
    case .good: .blue
    case .easy: .green
    }
  }
}

private struct CompleteView: View {
  let nextDueDate: Date?

  var body: some View {
    ContentUnavailableView {
      Label("All caught up", systemImage: "checkmark.circle.fill")
    } description: {
      if let nextDueDate {
        Text("Your next review is \(nextDueDate, format: .relative(presentation: .named)).")
      } else {
        Text("There are no cards to study.")
      }
    }
  }
}

private struct SettingsView: View {
  let store: StudyStore
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Progress") {
          Button("Reset this deck's progress", role: .destructive) { store.resetProgress() }
        }

        Section("Deck format") {
          Text("The first CSV column name is the speech language code, such as ja. Add readings after Japanese words with brackets: 日本語[にほんご].")
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .frame(minWidth: 360, minHeight: 320)
  }
}

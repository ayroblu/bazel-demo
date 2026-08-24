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
  @State private var confirmingReset = false

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
    .contextMenu {
      Button("Reset progress", systemImage: "arrow.counterclockwise", role: .destructive) {
        confirmingReset = true
      }
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
  @State private var speech = SpeechPlayer()
  @State private var showingSettings = false

  var body: some View {
    Group {
      if let card = store.currentCard {
        StudyCardView(card: card, store: store, speech: speech)
      } else {
        CompleteView(nextDueDate: store.nextDueDate)
      }
    }
    .onAppear {
      // Reopening a deck should start on the question, not a revealed answer.
      store.hideAnswer()
      store.advanceClock()
    }
    .onDisappear {
      speech.stop()
      if !showingSettings { store.hideAnswer() }
    }
    .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { now in
      store.advanceClock(to: now)
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
          speech.toggle(card.prompt, languageCode: card.languageCode)
        } label: {
          Label(
            speech.isPlaying ? "Stop" : "Play",
            systemImage: speech.isPlaying ? "stop.fill" : "play.fill"
          )
        }
        .buttonStyle(.bordered)
      }

      ScrollView {
        VStack(spacing: 24) {
          Spacer(minLength: 8)
          FuriganaText(source: card.prompt)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(FuriganaParser.speechText(card.prompt))

          if store.showingAnswer {
            Divider()
            if Romaji.isSupported(languageCode: card.languageCode),
              let romaji = Romaji.transliterate(card.prompt)
            {
              Text(romaji)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
            Text(card.answer)
              .font(.system(size: 40))
              .multilineTextAlignment(.center)
              .lineLimit(nil)
              .fixedSize(horizontal: false, vertical: true)
              .textSelection(.enabled)
          }
          Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity)
      }
      .scrollBounceBehavior(.basedOnSize)

      if store.showingAnswer {
        RatingButtons(store: store)
      } else {
        Button("Show answer") { store.revealAnswer() }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .keyboardShortcut(.space, modifiers: [])
      }
    }
    .padding()
    .frame(maxWidth: 720)
    .task(id: card.id) {
      // Each card starts speaking on repeat, so the button starts on Stop.
      speech.start(card.prompt, languageCode: card.languageCode)
    }
  }
}

private struct FuriganaText: View {
  let source: String

  var body: some View {
    WrappingRow(spacing: 0, lineSpacing: 8) {
      ForEach(Array(FuriganaParser.parse(source).enumerated()), id: \.offset) { _, segment in
        VStack(spacing: 1) {
          Text(segment.reading ?? " ")
            .font(.system(size: 24))
            .foregroundStyle(.secondary)
          Text(segment.text)
            .font(.system(size: 42, weight: .medium))
        }
        .fixedSize()
      }
    }
    .multilineTextAlignment(.center)
  }
}

/// Lays subviews out left to right, wrapping to a new line when the proposed width runs out.
private struct WrappingRow: Layout {
  var spacing: CGFloat
  var lineSpacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let lines = layoutLines(maxWidth: proposal.width ?? .infinity, subviews: subviews)
    let width = lines.map(\.width).max() ?? 0
    let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    var y = bounds.minY
    for line in layoutLines(maxWidth: bounds.width, subviews: subviews) {
      var x = bounds.minX + (bounds.width - line.width) / 2
      for index in line.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(
          at: CGPoint(x: x, y: y + line.height - size.height),
          proposal: ProposedViewSize(size)
        )
        x += size.width + spacing
      }
      y += line.height + lineSpacing
    }
  }

  private struct Line {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func layoutLines(maxWidth: CGFloat, subviews: Subviews) -> [Line] {
    var lines: [Line] = []
    var current = Line()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let added = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      if !current.indices.isEmpty, added > maxWidth {
        lines.append(current)
        current = Line()
      }
      current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      current.height = max(current.height, size.height)
      current.indices.append(index)
    }
    if !current.indices.isEmpty { lines.append(current) }
    return lines
  }
}

private struct RatingButtons: View {
  let store: StudyStore

  var body: some View {
    HStack(spacing: 8) { buttons }
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
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.roundedRectangle(radius: 6))
      .tint(tint(for: rating))
    }
  }

  private func intervalLabel(_ interval: TimeInterval) -> String {
    switch interval {
    case ..<3_600: "\(max(1, Int((interval / 60).rounded())))m"
    case ..<86_400: "\(Int((interval / 3_600).rounded()))h"
    case ..<(30 * 86_400): "\(Int((interval / 86_400).rounded()))d"
    case ..<(365 * 86_400): String(format: "%.1fmo", interval / (30.417 * 86_400))
    default: String(format: "%.1fy", interval / (365 * 86_400))
    }
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
  @State private var confirmingReset = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Progress") {
          Button("Reset this deck's progress", role: .destructive) { confirmingReset = true }
            .confirmationDialog(
              "Reset progress for this deck?",
              isPresented: $confirmingReset,
              titleVisibility: .visible
            ) {
              Button("Reset progress", role: .destructive) {
                store.resetProgress()
                dismiss()
              }
              Button("Cancel", role: .cancel) {}
            } message: {
              Text("Every card in this deck becomes new again. This cannot be undone.")
            }
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

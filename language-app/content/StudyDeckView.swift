import LanguageScheduler
import SwiftUI

struct StudyDeckView: View {
  let deck: Deck
  @Bindable var store: StudyStore
  @State private var speech = SpeechPlayer()
  @State private var showingSettings = false

  var body: some View {
    Group {
      if let card = store.currentCard {
        StudyCardView(card: card, store: store, speech: speech)
      } else if store.isDayComplete {
        DayCompleteView(store: store, speech: speech)
      } else {
        CompleteView(store: store, speech: speech, nextDueDate: store.nextDueDate)
      }
    }
    .onAppear {
      // Reopening a deck takes the next card, on its question rather than a revealed answer.
      store.advanceToNextCard()
    }
    .onChange(of: store.currentCard?.id) { _, cardId in
      if cardId == nil { speech.stop() }
    }
    .onDisappear {
      speech.stop()
      if !showingSettings { store.hideAnswer() }
    }
    .navigationTitle(deck.name)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Undo", systemImage: "arrow.uturn.backward") { store.undo() }
          .disabled(!store.canUndo)
          .keyboardShortcut("z", modifiers: .command)
      }
      ToolbarItem(placement: .primaryAction) {
        Button("Settings", systemImage: "gearshape") { showingSettings = true }
      }
    }
    .sheet(isPresented: $showingSettings) {
      SettingsView(
        store: store,
        speech: speech,
        languageCode: deck.languageCode,
        answerLanguageCode: deck.answerColumnName
      )
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
        QueueCountsView(counts: store.counts, highlighted: store.currentQueue)
        Spacer()
      }

      CardFaceView(card: card, showingAnswer: store.showingAnswer)

      VStack(spacing: 16) {
        HStack {
          SpeechToggleButton(
            card: card,
            speech: speech,
            rate: store.speechRate,
            times: store.showingAnswer ? 1 : StudyStore.autoSpeakRepeats
          )
          Spacer()
        }

        if store.showingAnswer {
          RatingButtons(
            interval: { store.previewInterval(for: $0) },
            grade: { store.grade($0) }
          )
        } else {
          Button { store.revealAnswer() } label: {
            Text("Show answer")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .keyboardShortcut(.space, modifiers: [])
        }
      }
    }
    .padding()
    .frame(maxWidth: 720)
    .onAppear { autoSpeak(card, times: StudyStore.autoSpeakRepeats) }
    .onChange(of: card.id) { _, _ in autoSpeak(card, times: StudyStore.autoSpeakRepeats) }
    .onChange(of: store.showingAnswer) { _, showing in
      guard showing else { return }
      autoSpeak(card, times: 1)
    }
  }

  private func autoSpeak(_ card: DeckCard, times: Int) {
    guard store.autoSpeak else { return }
    speech.start(
      card.prompt,
      languageCode: card.languageCode,
      rate: store.speechRate,
      times: times
    )
  }
}

private struct DayCompleteView: View {
  let store: StudyStore
  let speech: SpeechPlayer
  @State private var extraCards = 10

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: 52))
        .foregroundStyle(.green)
      Text("Day completed!")
        .font(.title.bold())
      Text(
        "You finished today's \(store.newCardsPerDay + store.extraCardsToday) new cards and every review that was due."
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)

      HStack(spacing: 8) {
        TextField("", value: $extraCards, format: .number)
          .textFieldStyle(.roundedBorder)
          .frame(width: 72)
          .multilineTextAlignment(.trailing)
          .accessibilityLabel("Extra cards")
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
        Button("Add cards today") { store.addExtraCardsToday(extraCards) }
          .buttonStyle(.borderedProminent)
          .disabled(extraCards < 1)
      }
      Text("Extra cards apply to today only.")
        .font(.caption)
        .foregroundStyle(.secondary)

      Divider()

      PracticeControls(store: store, speech: speech, order: .latestFirst)
    }
    .padding()
    .frame(maxWidth: 420)
  }
}

/// Starts an extra pass over cards already studied.
private struct PracticeControls: View {
  enum Order {
    case latestFirst
    case random
  }

  let store: StudyStore
  let speech: SpeechPlayer
  let order: Order
  @State private var count = 0
  @State private var practice: PracticeSet?

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        TextField("", value: $count, format: .number)
          .textFieldStyle(.roundedBorder)
          .frame(width: 72)
          .multilineTextAlignment(.trailing)
          .accessibilityLabel("Cards to review")
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
        Button("Review past cards") { practice = PracticeSet(cards: selection) }
          .buttonStyle(.bordered)
          .disabled(count < 1 || studiedCount == 0)
      }
      Text(caption)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .onAppear { count = studiedCount }
    .sheet(item: $practice) { set in
      PracticeView(
        cards: set.cards,
        speech: speech,
        speechRate: store.speechRate,
        autoSpeak: store.autoSpeak
      )
    }
  }

  private var caption: String {
    switch order {
    case .latestFirst:
      "The cards you have seen, latest first. Answers here do not change their scheduling."
    case .random:
      "A random pass over cards you have seen. Answers here do not change their scheduling."
    }
  }

  private var selection: [DeckCard] {
    switch order {
    case .latestFirst: store.recentStudiedCards(count: count)
    case .random: store.randomStudiedCards(count: count)
    }
  }

  private var studiedCount: Int { store.studiedCards.count }
}

private struct PracticeSet: Identifiable {
  let id = UUID()
  let cards: [DeckCard]
}

private struct PracticeView: View {
  let speech: SpeechPlayer
  let speechRate: Double
  let autoSpeak: Bool
  @Environment(\.dismiss) private var dismiss
  @State private var session: PracticeSession

  init(cards: [DeckCard], speech: SpeechPlayer, speechRate: Double, autoSpeak: Bool) {
    self.speech = speech
    self.speechRate = speechRate
    self.autoSpeak = autoSpeak
    _session = State(initialValue: PracticeSession(cards: cards))
  }

  var body: some View {
    NavigationStack {
      Group {
        if let card = session.currentCard {
          VStack(spacing: 24) {
            CardFaceView(card: card, showingAnswer: session.showingAnswer) {
              HStack {
                Text("\(session.remaining) left")
                  .font(.subheadline)
                  .monospacedDigit()
                  .foregroundStyle(.secondary)
                Spacer()
              }
            }

            VStack(spacing: 16) {
              HStack {
                SpeechToggleButton(
                  card: card,
                  speech: speech,
                  rate: speechRate,
                  times: session.showingAnswer ? 1 : StudyStore.autoSpeakRepeats
                )
                Spacer()
              }

              if session.showingAnswer {
                RatingButtons(
                  interval: { session.previewInterval(for: $0) },
                  grade: { session.grade($0) }
                )
              } else {
                Button { session.revealAnswer() } label: {
                  Text("Show answer")
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.space, modifiers: [])
              }
            }
          }
          .padding()
          .frame(maxWidth: 720)
          .onAppear { speak(card, times: StudyStore.autoSpeakRepeats) }
          .onChange(of: card.id) { _, _ in speak(card, times: StudyStore.autoSpeakRepeats) }
          .onChange(of: session.showingAnswer) { _, showing in
            guard showing else { return }
            speak(card, times: 1)
          }
        } else {
          ContentUnavailableView(
            "Review finished",
            systemImage: "checkmark.circle.fill",
            description: Text("Nothing left in this pass.")
          )
        }
      }
      .navigationTitle("Review past cards")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Undo", systemImage: "arrow.uturn.backward") { session.undo() }
            .disabled(!session.canUndo)
            .keyboardShortcut("z", modifiers: .command)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .onDisappear { speech.stop() }
    #if os(macOS)
      .frame(minWidth: 480, minHeight: 520)
    #endif
  }

  private func speak(_ card: DeckCard, times: Int) {
    guard autoSpeak else { return }
    speech.start(card.prompt, languageCode: card.languageCode, rate: speechRate, times: times)
  }
}

private struct CompleteView: View {
  let store: StudyStore
  let speech: SpeechPlayer
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
    } actions: {
      PracticeControls(store: store, speech: speech, order: .random)
    }
  }
}

private struct RatingButtons: View {
  let interval: (CardRating) -> TimeInterval
  let grade: (CardRating) -> Void

  var body: some View {
    HStack(spacing: 8) { buttons }
  }

  @ViewBuilder
  private var buttons: some View {
    ForEach(CardRating.allCases, id: \.rawValue) { rating in
      Button {
        grade(rating)
      } label: {
        VStack(spacing: 2) {
          Text(title(for: rating))
          Text(intervalLabel(interval(rating)))
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

  private func title(for rating: CardRating) -> String {
    switch rating {
    case .again: "Again"
    case .hard: "Hard"
    case .good: "Good"
    case .easy: "Easy"
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

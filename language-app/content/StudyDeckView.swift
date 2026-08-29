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
        DayCompleteView(store: store)
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
        QueueCountsView(counts: store.counts)
        Spacer()
      }

      CardFaceView(card: card, showingAnswer: store.showingAnswer)

      VStack(spacing: 16) {
        HStack {
          SpeechToggleButton(card: card, speech: speech, rate: store.speechRate)
          Spacer()
        }

        if store.showingAnswer {
          RatingButtons(store: store)
        } else {
          Button("Show answer") { store.revealAnswer() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.space, modifiers: [])
        }
      }
    }
    .padding()
    .frame(maxWidth: 720)
    // The first card starts speaking on repeat, so the button starts on Stop. Later cards
    // only speak if the previous one was still playing. This runs on the main run loop
    // instead of in a task, keeping speech off Swift concurrency threads.
    .onAppear {
      speech.start(card.prompt, languageCode: card.languageCode, rate: store.speechRate)
    }
    .onChange(of: card.id) { _, _ in
      guard speech.isPlaying else { return }
      speech.start(card.prompt, languageCode: card.languageCode, rate: store.speechRate)
    }
  }
}

private struct DayCompleteView: View {
  let store: StudyStore
  @State private var extraCards = 10

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: 52))
        .foregroundStyle(.green)
      Text("Day completed!")
        .font(.title.bold())
      Text("You finished today's \(store.newCardsPerDay + store.extraCardsToday) new cards and every review that was due.")
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
    }
    .padding()
    .frame(maxWidth: 420)
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
          Text(title(for: rating))
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

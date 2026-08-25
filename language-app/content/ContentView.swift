import AVFoundation
import SwiftUI

public struct ContentView: View {
  @State private var decks = DeckStore()
  @State private var importing = false
  @State private var creating = false
  @State private var errorMessage: String?

  public init() {}

  public var body: some View {
    NavigationStack {
      Group {
        if decks.decks.isEmpty {
          ContentUnavailableView(
            "No decks",
            systemImage: "rectangle.stack.badge.minus",
            description: Text(decks.errors.joined(separator: "\n"))
          )
        } else {
          List(decks.decks) { deck in
            DeckLink(deck: deck, decks: decks)
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
  @State private var store: StudyStore
  @State private var confirmingReset = false
  @State private var confirmingDelete = false
  @State private var inspecting = false

  init(deck: Deck, decks: DeckStore) {
    self.deck = deck
    self.decks = decks
    _store = State(initialValue: StudyStore(deck: deck))
  }

  var body: some View {
    NavigationLink {
      StudyDeckView(deck: deck, store: store)
    } label: {
      DeckRow(deck: deck, store: store)
    }
    .contextMenu {
      Button("Inspect deck", systemImage: "list.bullet.rectangle") { inspecting = true }
      Button("Reset progress", systemImage: "arrow.counterclockwise", role: .destructive) {
        confirmingReset = true
      }
      Button("Delete deck", systemImage: "trash", role: .destructive) {
        confirmingDelete = true
      }
    }
    // Deleting a deck cannot be undone, so a swipe opens the same confirmation.
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
    }
    // The deck file can change while this row is on screen, so the study queue follows it.
    .onChange(of: deck) { _, updated in store.updateDeck(updated) }
    .sheet(isPresented: $inspecting) {
      DeckInspectorView(deck: deck, decks: decks, store: store)
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
    .confirmationDialog(
      "Delete \(deck.name)?",
      isPresented: $confirmingDelete,
      titleVisibility: .visible
    ) {
      Button("Delete deck", role: .destructive) { try? decks.delete(deck) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The deck file and its \(deck.cards.count) cards are removed from this device.")
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

private struct StudyDeckView: View {
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
      SettingsView(store: store, speech: speech, languageCode: deck.languageCode)
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
    // Each card starts speaking on repeat, so the button starts on Stop. This runs on the
    // main run loop instead of in a task, keeping speech off Swift concurrency threads.
    .onAppear { speech.start(card.prompt, languageCode: card.languageCode) }
    .onChange(of: card.id) { _, _ in
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

private struct DeckInspectorView: View {
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

private struct QueueCountsView: View {
  let counts: QueueCounts

  var body: some View {
    HStack(spacing: 8) {
      value(counts.new, tint: .blue, name: "new")
      value(counts.learning, tint: .red, name: "again")
      value(counts.review, tint: .green, name: "review")
    }
    .monospacedDigit()
    .lineLimit(1)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(counts.new) new, \(counts.learning) again today, \(counts.review) to review")
  }

  private func value(_ count: Int, tint: Color, name: String) -> some View {
    HStack(spacing: 3) {
      Text("\(count)")
        .fontWeight(.semibold)
      Text(name)
    }
    .foregroundStyle(count > 0 ? tint : Color.secondary)
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

private struct SettingsView: View {
  @Bindable var store: StudyStore
  let speech: SpeechPlayer
  let languageCode: String
  @Environment(\.dismiss) private var dismiss
  @State private var confirmingReset = false

  #if os(macOS)
    private static let voiceDownloadHint =
      "Compact voices sound robotic. Add an enhanced or premium voice in System Settings › Accessibility › Spoken Content › System Voice › Manage Voices, then pick it here."
  #else
    private static let voiceDownloadHint =
      "Compact voices sound robotic. Add an enhanced or premium voice in Settings › Accessibility › Read & Speak › Voices (Spoken Content before iOS 26), then pick it here."
  #endif

  private var availableVoices: [AVSpeechSynthesisVoice] {
    VoiceCatalog.voices(for: languageCode)
  }

  private var voiceSelection: Binding<String> {
    Binding(
      get: { speech.voices.voice(for: languageCode)?.identifier ?? "" },
      set: { identifier in
        speech.voices.select(identifier.isEmpty ? nil : identifier, for: languageCode)
        // The new voice applies to the next playback.
        speech.stop()
      }
    )
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          if availableVoices.isEmpty {
            Text("No installed voice speaks \(languageCode).")
          } else {
            Picker("Voice", selection: voiceSelection) {
              ForEach(availableVoices, id: \.identifier) { voice in
                Text(VoiceCatalog.describe(voice)).tag(voice.identifier)
              }
            }
          }
        } header: {
          Text("Voice")
        } footer: {
          Text(Self.voiceDownloadHint)
        }

        Section {
          LabeledContent("New cards per day") {
            TextField("", value: $store.newCardsPerDay, format: .number)
              .multilineTextAlignment(.trailing)
              .frame(width: 72)
              .accessibilityLabel("New cards per day")
              #if os(iOS)
                .keyboardType(.numberPad)
              #endif
          }
        } header: {
          Text("Study")
        } footer: {
          Text("Unseen cards enter the queue up to this many per day. Reviews are never capped.")
        }

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

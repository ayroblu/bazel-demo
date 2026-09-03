import SwiftUI

struct BrowseDeckView: View {
  let deck: Deck
  let speechRate: Double
  let questionRepeats: Int
  @Environment(\.dismiss) private var dismiss
  @State private var speech = SpeechPlayer()
  @State private var session: BrowseSession
  @State private var mode: PlaybackMode = .off
  @State private var autoStep = 0
  @State private var showingSettings = false

  private enum PlaybackMode {
    case read
    case off
    case auto
  }

  init(deck: Deck, speechRate: Double, questionRepeats: Int, shuffled: Bool = false) {
    self.deck = deck
    self.speechRate = speechRate
    self.questionRepeats = questionRepeats
    _session = State(initialValue: BrowseSession(cards: deck.cards, shuffled: shuffled))
  }

  var body: some View {
    NavigationStack {
      Group {
        if let card = session.card {
          VStack(spacing: 24) {
            CardFaceView(card: card, showingAnswer: session.showingAnswer) {
              HStack {
                Text("\(session.index + 1) of \(deck.cards.count)")
                  .font(.subheadline)
                  .monospacedDigit()
                  .foregroundStyle(.secondary)
                Spacer()
              }
            }

            VStack(spacing: 16) {
              Picker("Playback", selection: $mode) {
                Text("Read").tag(PlaybackMode.read)
                Text("No audio").tag(PlaybackMode.off)
                Text("Auto").tag(PlaybackMode.auto)
              }
              .pickerStyle(.segmented)
              .labelsHidden()

              HStack(spacing: 12) {
                Button("Previous", systemImage: "chevron.left") {
                  session.back()
                  restartAutoIfRunning()
                }
                .frame(maxWidth: .infinity)
                .disabled(!session.canGoBack)
                .keyboardShortcut(.leftArrow, modifiers: [])
                Button(
                  session.showingAnswer ? "Next card" : "Show answer",
                  systemImage: "chevron.right"
                ) {
                  session.forward()
                  restartAutoIfRunning()
                }
                .frame(maxWidth: .infinity)
                .disabled(!session.canGoForward)
                .keyboardShortcut(.rightArrow, modifiers: [])
              }
              .buttonStyle(.bordered)
              .controlSize(.large)
              .labelStyle(.iconOnly)
            }
          }
          .padding()
          .frame(maxWidth: 720)
          .onAppear {
            speech.onRemotePlay = { mode = .auto }
            speech.onRemotePause = { mode = .off }
            apply(mode, card: card)
          }
          .onChange(of: mode) { _, newMode in
            apply(newMode, card: card)
          }
          .onChange(of: card.id) { _, _ in
            guard mode == .read else { return }
            speech.start(card.prompt, languageCode: card.languageCode, rate: speechRate)
          }
        } else {
          ContentUnavailableView(
            "No cards",
            systemImage: "rectangle.stack.badge.minus",
            description: Text("Add cards from this deck's Inspect deck menu.")
          )
        }
      }
      .navigationTitle(deck.name)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Voices", systemImage: "gearshape") {
            mode = .off
            showingSettings = true
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(isPresented: $showingSettings) {
        VoiceSettingsView(
          speech: speech,
          languageCode: deck.languageCode,
          answerLanguageCode: deck.answerColumnName
        )
      }
    }
    .onDisappear {
      mode = .off
      speech.onRemotePlay = nil
      speech.onRemotePause = nil
      speech.stop()
    }
    #if os(macOS)
      .frame(minWidth: 480, minHeight: 520)
    #endif
  }

  private func apply(_ mode: PlaybackMode, card: DeckCard) {
    switch mode {
    case .read:
      speech.start(card.prompt, languageCode: card.languageCode, rate: speechRate)
    case .off:
      speech.stop()
    case .auto:
      startAuto()
    }
  }

  private func startAuto() {
    speech.stop()
    autoStep = 0
    playAutoStep()
  }

  private func restartAutoIfRunning() {
    guard mode == .auto else { return }
    autoStep = 0
    playAutoStep()
  }

  private func playAutoStep() {
    guard mode == .auto, let card = session.card else { return }
    let steps = AutoBrowse.steps(questionRepeats: questionRepeats)
    guard autoStep < steps.count else {
      guard session.nextCard() else {
        mode = .off
        return
      }
      autoStep = 0
      return playAutoStep()
    }
    let step = steps[autoStep]
    if step == .answer { session.reveal() }
    speech.speakOnce(
      step == .question ? card.prompt : card.answer,
      languageCode: step == .question ? card.languageCode : deck.answerColumnName,
      rate: speechRate
    ) {
      guard mode == .auto else { return }
      autoStep += 1
      playAutoStep()
    }
  }
}

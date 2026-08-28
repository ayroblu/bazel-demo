import SwiftUI

struct BrowseDeckView: View {
  let deck: Deck
  let speechRate: Double
  let questionRepeats: Int
  @Environment(\.dismiss) private var dismiss
  @State private var speech = SpeechPlayer()
  @State private var session: BrowseSession
  @State private var autoRunning = true
  @State private var autoStep = 0
  @State private var showingSettings = false

  init(deck: Deck, speechRate: Double, questionRepeats: Int) {
    self.deck = deck
    self.speechRate = speechRate
    self.questionRepeats = questionRepeats
    _session = State(initialValue: BrowseSession(cards: deck.cards))
  }

  var body: some View {
    NavigationStack {
      Group {
        if let card = session.card {
          VStack(spacing: 24) {
            HStack {
              Text("\(session.index + 1) of \(deck.cards.count)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
              Spacer()
            }

            CardFaceView(card: card, showingAnswer: session.showingAnswer)

            VStack(spacing: 16) {
              HStack {
                SpeechToggleButton(card: card, speech: speech, rate: speechRate)
                  .disabled(autoRunning)
                Spacer()
                Button {
                  autoRunning ? stopAuto() : startAuto()
                } label: {
                  Label(
                    autoRunning ? "Stop auto" : "Auto",
                    systemImage: autoRunning ? "stop.fill" : "play.fill"
                  )
                }
                .buttonStyle(.bordered)
              }

              HStack(spacing: 12) {
                Button("Previous", systemImage: "chevron.left") {
                  session.back()
                  restartAutoIfRunning()
                }
                .disabled(!session.canGoBack)
                .keyboardShortcut(.leftArrow, modifiers: [])
                Spacer()
                Button(
                  session.showingAnswer ? "Next card" : "Show answer",
                  systemImage: "chevron.right"
                ) {
                  session.forward()
                  restartAutoIfRunning()
                }
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
            speech.onRemotePlay = { startAuto() }
            speech.onRemotePause = { stopAuto() }
            guard autoRunning else { return }
            startAuto()
          }
          .onChange(of: card.id) { _, _ in
            guard !autoRunning, speech.isPlaying else { return }
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
            stopAuto()
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
      autoRunning = false
      speech.onRemotePlay = nil
      speech.onRemotePause = nil
      speech.stop()
    }
    #if os(macOS)
      .frame(minWidth: 480, minHeight: 520)
    #endif
  }

  private func startAuto() {
    speech.stop()
    autoStep = 0
    autoRunning = true
    playAutoStep()
  }

  private func stopAuto() {
    autoRunning = false
    speech.stop()
  }

  private func restartAutoIfRunning() {
    guard autoRunning else { return }
    autoStep = 0
    playAutoStep()
  }

  private func playAutoStep() {
    guard autoRunning, let card = session.card else { return }
    let steps = AutoBrowse.steps(questionRepeats: questionRepeats)
    guard autoStep < steps.count else {
      guard session.nextCard() else { return stopAuto() }
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
      guard autoRunning else { return }
      autoStep += 1
      playAutoStep()
    }
  }
}

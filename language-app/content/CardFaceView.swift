import SwiftUI

struct CardFaceView<Header: View>: View {
  let card: DeckCard
  let showingAnswer: Bool
  @ViewBuilder let header: Header

  init(card: DeckCard, showingAnswer: Bool, @ViewBuilder header: () -> Header) {
    self.card = card
    self.showingAnswer = showingAnswer
    self.header = header()
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        header
        Spacer(minLength: 8)
        FuriganaText(source: card.prompt)
          .frame(maxWidth: .infinity)
          .accessibilityLabel(FuriganaParser.speechText(card.prompt))

        if showingAnswer {
          Divider()
          if Romaji.isSupported(languageCode: card.languageCode),
            let romaji = Romaji.transliterate(card.prompt),
            romaji != card.answer
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
  }
}

extension CardFaceView where Header == EmptyView {
  init(card: DeckCard, showingAnswer: Bool) {
    self.init(card: card, showingAnswer: showingAnswer) { EmptyView() }
  }
}

struct SpeechToggleButton: View {
  let card: DeckCard
  let speech: SpeechPlayer
  let rate: Double
  var times: Int = 1

  var body: some View {
    Button {
      speech.toggle(card.prompt, languageCode: card.languageCode, rate: rate, times: times)
    } label: {
      Label(
        speech.isPlaying ? "Stop" : "Speak",
        systemImage: speech.isPlaying ? "stop.fill" : "play.fill"
      )
    }
    .buttonStyle(.bordered)
  }
}

struct QueueCountsView: View {
  let counts: QueueCounts
  var highlighted: QueueKind?

  var body: some View {
    HStack(spacing: 8) {
      value(counts.new, tint: .blue, name: "new", queue: .new)
      value(counts.learning, tint: .red, name: "again", queue: .learning)
      value(counts.review, tint: .green, name: "review", queue: .review)
    }
    .monospacedDigit()
    .lineLimit(1)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    let counted =
      "\(counts.new) new, \(counts.learning) again today, \(counts.review) to review"
    switch highlighted {
    case .new: return counted + ", showing a new card"
    case .learning: return counted + ", showing an again card"
    case .review: return counted + ", showing a review card"
    case nil: return counted
    }
  }

  private func value(_ count: Int, tint: Color, name: String, queue: QueueKind) -> some View {
    HStack(spacing: 3) {
      Text("\(count)")
        .fontWeight(.semibold)
      Text(name)
    }
    .foregroundStyle(count > 0 ? tint : Color.secondary)
    .underline(highlighted == queue)
  }
}

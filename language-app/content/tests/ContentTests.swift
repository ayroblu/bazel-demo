import Foundation
import Testing
@testable import LanguageContent

@MainActor
@Test func parsesQuotedCSVAndLanguageHeader() throws {
  let csv = "ja,en\n日本語[にほんご],\"Japanese, the language\"\n"
  let deck = try CSVDeckLoader.load(name: "Test", data: Data(csv.utf8))
  #expect(deck.languageCode == "ja")
  #expect(deck.cards.count == 1)
  #expect(deck.cards[0].answer == "Japanese, the language")
}

@MainActor
@Test func loadsMultipleDecksFromCSVData() throws {
  let japanese = try CSVDeckLoader.load(name: "Japanese", data: Data("ja,en\n猫[ねこ],cat\n".utf8))
  let spanish = try CSVDeckLoader.load(name: "Spanish", data: Data("es,en\nhola,hello\n".utf8))
  let library = DeckLibrary(decks: [japanese, spanish])
  #expect(library.decks.map(\.languageCode) == ["ja", "es"])
  #expect(Set(library.decks.map(\.id)).count == 2)
}

@MainActor
@Test func keepsDeckProgressSeparate() throws {
  let suite = "language-app-tests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }

  let japanese = try CSVDeckLoader.load(name: "Japanese", data: Data("ja,en\n猫[ねこ],cat\n".utf8))
  let spanish = try CSVDeckLoader.load(name: "Spanish", data: Data("es,en\ngato,cat\n".utf8))
  let japaneseStore = StudyStore(deck: japanese, defaults: defaults)
  let spanishStore = StudyStore(deck: spanish, defaults: defaults)

  japaneseStore.grade(.good, now: Date(timeIntervalSince1970: 1_700_000_000))
  #expect(japaneseStore.reviewStates.count == 1)
  #expect(spanishStore.reviewStates.isEmpty)
  #expect(StudyStore(deck: japanese, defaults: defaults).reviewStates.count == 1)
  #expect(StudyStore(deck: spanish, defaults: defaults).reviewStates.isEmpty)
}

@MainActor
@Test func parsesFuriganaAnnotations() {
  let segments = FuriganaParser.parse("今日[きょう]は猫[ねこ]です")
  #expect(segments == [
    FuriganaSegment(text: "今日", reading: "きょう"),
    FuriganaSegment(text: "は"),
    FuriganaSegment(text: "猫", reading: "ねこ"),
    FuriganaSegment(text: "です"),
  ])
  #expect(FuriganaParser.displayText("食[た]べる") == "食べる")
  #expect(FuriganaParser.speechText("食[た]べる") == "たべる")
}

@MainActor
@Test func resettingProgressMakesEveryCardNewAgain() throws {
  let csv = "ja,en\n猫[ねこ],cat\n犬[いぬ],dog\n"
  let deck = try CSVDeckLoader.load(name: "Japanese", data: Data(csv.utf8))
  let suite = "reset-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }

  let store = StudyStore(deck: deck, defaults: defaults)
  store.grade(.easy)
  #expect(store.reviewStates.count == 1)
  #expect(store.dueCards.count == 1)

  store.resetProgress()
  #expect(store.reviewStates.isEmpty)
  #expect(store.dueCards.count == 2)
  // The reset must survive relaunching, not just clear memory.
  #expect(StudyStore(deck: deck, defaults: defaults).reviewStates.isEmpty)
}

@MainActor
@Test func voiceCatalogRanksRealVoicesAheadOfNoveltyVoices() throws {
  let japanese = VoiceCatalog.voices(for: "ja")
  #expect(!japanese.isEmpty)
  #expect(japanese.allSatisfy { $0.language.lowercased().hasPrefix("ja") })

  let best = try #require(japanese.first)
  #expect(!best.identifier.hasPrefix("com.apple.eloquence."))
  #expect(VoiceCatalog.preferred(for: "ja")?.identifier == best.identifier)
  #expect(VoiceCatalog.voices(for: "zz").isEmpty)
}

@MainActor
@Test func voicePreferencesPersistPerLanguage() throws {
  let suite = "voices-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }

  let preferences = VoicePreferences(defaults: defaults)
  let fallback = try #require(preferences.voice(for: "ja"))
  #expect(preferences.selectedIdentifier(for: "ja") == nil)

  let alternative = try #require(
    VoiceCatalog.voices(for: "ja").first { $0.identifier != fallback.identifier })
  preferences.select(alternative.identifier, for: "ja")
  #expect(preferences.voice(for: "ja")?.identifier == alternative.identifier)
  #expect(VoicePreferences(defaults: defaults).voice(for: "ja")?.identifier == alternative.identifier)

  // Choosing a Japanese voice must not change other languages.
  #expect(VoicePreferences(defaults: defaults).selectedIdentifier(for: "es") == nil)

  preferences.select(nil, for: "ja")
  #expect(preferences.voice(for: "ja")?.identifier == fallback.identifier)
}

@MainActor
@Test func speechPlayerTracksPlaybackState() {
  let player = SpeechPlayer()
  #expect(!player.isPlaying)

  player.start("猫[ねこ]", languageCode: "ja")
  #expect(player.isPlaying)

  player.stop()
  #expect(!player.isPlaying)

  player.toggle("猫[ねこ]", languageCode: "ja")
  #expect(player.isPlaying)
  player.toggle("猫[ねこ]", languageCode: "ja")
  #expect(!player.isPlaying)
}

@MainActor
@Test func hidingTheAnswerReturnsToTheQuestion() throws {
  let deck = try CSVDeckLoader.load(name: "Japanese", data: Data("ja,en\n猫[ねこ],cat\n".utf8))
  let defaults = try #require(UserDefaults(suiteName: "reveal-\(UUID().uuidString)"))
  let store = StudyStore(deck: deck, defaults: defaults)

  store.revealAnswer()
  #expect(store.showingAnswer)
  store.hideAnswer()
  #expect(!store.showingAnswer)
}

@MainActor
@Test func walksAnkiLearningStepsBeforeGraduating() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)

  let again = FSRSScheduler.review(nil, rating: .again, now: now)
  #expect(again.scheduledInterval == 60)
  #expect(again.phase == .learning)
  #expect(again.lapses == 0)

  let hard = FSRSScheduler.review(nil, rating: .hard, now: now)
  #expect(hard.scheduledInterval == 330)
  #expect(hard.step == 0)

  let firstStep = FSRSScheduler.review(nil, rating: .good, now: now)
  #expect(firstStep.scheduledInterval == 600)
  #expect(firstStep.phase == .learning)
  #expect(firstStep.step == 1)
  #expect(firstStep.reps == 1)

  let graduated = FSRSScheduler.review(firstStep, rating: .good, now: now.addingTimeInterval(600))
  #expect(graduated.phase == .review)
  #expect(graduated.scheduledInterval >= 86_400)
  #expect(graduated.stability > firstStep.stability)
  #expect(graduated.due > now.addingTimeInterval(600))

  // Easy skips the remaining steps and hands the card straight to FSRS.
  let easy = FSRSScheduler.review(nil, rating: .easy, now: now)
  #expect(easy.phase == .review)
  #expect(easy.scheduledInterval > graduated.scheduledInterval)
}

@MainActor
@Test func lapsedReviewCardEntersRelearningSteps() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let firstStep = FSRSScheduler.review(nil, rating: .good, now: now)
  let graduated = FSRSScheduler.review(firstStep, rating: .good, now: now.addingTimeInterval(600))

  let lapseTime = graduated.due
  let lapsed = FSRSScheduler.review(graduated, rating: .again, now: lapseTime)
  #expect(lapsed.phase == .relearning)
  #expect(lapsed.scheduledInterval == 600)
  #expect(lapsed.lapses == 1)
  #expect(lapsed.stability <= graduated.stability)

  let recovered = FSRSScheduler.review(lapsed, rating: .good, now: lapseTime.addingTimeInterval(600))
  #expect(recovered.phase == .review)
  #expect(recovered.scheduledInterval >= 86_400)
  #expect(recovered.lapses == 1)
}

@MainActor
@Test func intervalsGrowAcrossSuccessfulReviews() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  var state = FSRSScheduler.review(
    FSRSScheduler.review(nil, rating: .good, now: now),
    rating: .good,
    now: now.addingTimeInterval(600)
  )
  var previous = state.scheduledInterval
  for _ in 1...4 {
    state = FSRSScheduler.review(state, rating: .good, now: state.due)
    #expect(state.scheduledInterval > previous)
    previous = state.scheduledInterval
  }
}

@MainActor
@Test func dueQueueHonoursLearningStepsUntilTheClockAdvances() throws {
  let csv = "ja,en\n猫[ねこ],cat\n犬[いぬ],dog\n"
  let deck = try CSVDeckLoader.load(name: "Japanese", data: Data(csv.utf8))
  let defaults = try #require(UserDefaults(suiteName: "steps-\(UUID().uuidString)"))
  defer { defaults.removePersistentDomain(forName: "steps") }
  let store = StudyStore(deck: deck, defaults: defaults)
  let now = Date()

  #expect(store.dueCards.count == 2)
  store.grade(.again, now: now)
  #expect(store.dueCards.count == 1)

  store.advanceClock(to: now.addingTimeInterval(61))
  #expect(store.dueCards.count == 2)
}

@MainActor
@Test func transliteratesFuriganaReadingsToRomaji() {
  #expect(
    Romaji.transliterate("毎日[まいにち]日本語[にほんご]を勉強[べんきょう]します")
      == "mainichi nihongo o benkyoushimasu")
  #expect(Romaji.transliterate("猫[ねこ]") == "neko")
  #expect(Romaji.transliterate("el gato") == nil)
  #expect(Romaji.isSupported(languageCode: "ja"))
  #expect(!Romaji.isSupported(languageCode: "es"))
}

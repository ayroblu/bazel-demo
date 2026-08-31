import AVFoundation
import Foundation
import LanguageScheduler
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
@Test func loadsEveryBundledDeck() throws {
  let directory = URL(filePath: FileManager.default.currentDirectoryPath)
    .appending(path: "language-app/decks")
  let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "csv" }
  #expect(files.count >= 4)
  for file in files {
    let deck = try CSVDeckLoader.load(
      name: file.deletingPathExtension().lastPathComponent, data: try Data(contentsOf: file))
    #expect(!deck.cards.isEmpty)
    #expect(Set(deck.cards.map(\.prompt)).count == deck.cards.count)
  }
}

@MainActor
@Test func fillsAnEmptyJapaneseAnswerWithRomaji() throws {
  let deck = try CSVDeckLoader.load(name: "Kana", data: Data("ja,en\nき,\nきゃ,\nは,ha\n".utf8))
  #expect(deck.cards.map(\.answer) == ["ki", "kya", "ha"])
}

@MainActor
@Test func rejectsAnEmptyAnswerWithoutRomaji() throws {
  #expect(throws: CSVDeckError.invalidRow(2)) {
    try CSVDeckLoader.load(name: "Spanish", data: Data("es,en\nhola,\n".utf8))
  }
}

@MainActor
private func emptyDeckStore() throws -> (store: DeckStore, directory: URL, defaults: UserDefaults) {
  let directory = URL.temporaryDirectory.appending(path: "decks-\(UUID().uuidString)")
  let defaults = try #require(UserDefaults(suiteName: "decks-\(UUID().uuidString)"))
  return (DeckStore(directory: directory, bundledDecks: [], defaults: defaults), directory, defaults)
}

@MainActor
@Test func loadsEveryDeckFileInTheDecksFolder() throws {
  let (store, directory, defaults) = try emptyDeckStore()
  try Data("ja,en\n猫[ねこ],cat\n".utf8).write(to: directory.appending(path: "japanese.csv"))
  try Data("es,en\nhola,hello\n".utf8).write(to: directory.appending(path: "spanish.csv"))

  let reopened = DeckStore(directory: directory, bundledDecks: [], defaults: defaults)
  #expect(store.decks.isEmpty)
  #expect(reopened.decks.map(\.name) == ["Japanese", "Spanish"])
  #expect(reopened.decks.map(\.languageCode) == ["ja", "es"])
  #expect(Set(reopened.decks.map(\.id)).count == 2)
}

@MainActor
@Test func editsToABundledDeckSurviveRelaunching() throws {
  let directory = URL.temporaryDirectory.appending(path: "seed-\(UUID().uuidString)")
  let bundled = URL.temporaryDirectory.appending(path: "bundle-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
  let source = bundled.appending(path: "anime.csv")
  try Data("ja,en\n猫[ねこ],cat\n犬[いぬ],dog\n".utf8).write(to: source)
  let defaults = try #require(UserDefaults(suiteName: "seed-\(UUID().uuidString)"))

  func launch() -> DeckStore {
    DeckStore(directory: directory, bundledDecks: [source], defaults: defaults)
  }

  // First launch copies the bundled deck in.
  let first = launch()
  var deck = try #require(first.decks.first)
  #expect(deck.name == "Anime")
  #expect(deck.cards.count == 2)

  // The reader rewrites a card and adds one.
  deck.cards[0] = DeckCard(prompt: "猫[ねこ]", answer: "a cat, edited", languageCode: "ja")
  deck.cards.append(DeckCard(prompt: "鳥[とり]", answer: "bird", languageCode: "ja"))
  try first.replace(deck)

  // Relaunching must not put the bundled copy back over the edit.
  let second = launch()
  let reopened = try #require(second.decks.first)
  #expect(reopened.cards.count == 3)
  #expect(reopened.cards[0].answer == "a cat, edited")

  // A newer bundled deck still leaves the edited copy alone.
  try Data("ja,en\n猫[ねこ],cat\n犬[いぬ],dog\n魚[さかな],fish\n".utf8).write(to: source)
  #expect(try #require(launch().decks.first).cards.count == 3)

  // Deleting the deck lets the bundled copy seed again, now at its newer contents.
  try second.delete(reopened)
  #expect(try #require(launch().decks.first).cards.count == 3)
  #expect(try #require(launch().decks.first).cards[2].prompt == "魚[さかな]")
}

@MainActor
@Test func anUneditedBundledDeckIsRefreshedWhenTheBundleChanges() throws {
  let directory = URL.temporaryDirectory.appending(path: "refresh-\(UUID().uuidString)")
  let bundled = URL.temporaryDirectory.appending(path: "bundle-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
  let source = bundled.appending(path: "japanese.csv")
  try Data("ja,en\n猫[ねこ],cat\n".utf8).write(to: source)
  let defaults = try #require(UserDefaults(suiteName: "refresh-\(UUID().uuidString)"))

  func launch() -> DeckStore {
    DeckStore(directory: directory, bundledDecks: [source], defaults: defaults)
  }
  #expect(try #require(launch().decks.first).cards.count == 1)

  try Data("ja,en\n猫[ねこ],cat\n犬[いぬ],dog\n".utf8).write(to: source)
  #expect(try #require(launch().decks.first).cards.count == 2)
}

@MainActor
@Test func deckStoreCreatesEditsAndDeletes() throws {
  let (store, directory, defaults) = try emptyDeckStore()

  var deck = try store.createDeck(name: "My Verbs", languageCode: "JA", answerColumnName: "en")
  #expect(deck.languageCode == "ja")
  #expect(store.decks.map(\.name) == ["My Verbs"])
  #expect(throws: DeckStoreError.duplicateName("My Verbs")) {
    _ = try store.createDeck(name: "My Verbs", languageCode: "ja", answerColumnName: "en")
  }

  deck.cards = [
    DeckCard(prompt: "走[はし]る", answer: "to run", languageCode: "ja"),
    DeckCard(prompt: "歩[ある]く", answer: "to walk; on foot, slowly", languageCode: "ja"),
  ]
  try store.replace(deck)

  let reopened = DeckStore(directory: directory, bundledDecks: [], defaults: defaults)
  let saved = try #require(reopened.deck(id: deck.id))
  #expect(saved.cards.map(\.prompt) == ["走[はし]る", "歩[ある]く"])
  // A comma in an answer has to survive the CSV round trip.
  #expect(saved.cards[1].answer == "to walk; on foot, slowly")

  try store.delete(deck)
  #expect(store.decks.isEmpty)
  #expect(DeckStore(directory: directory, bundledDecks: [], defaults: defaults).decks.isEmpty)
}

@MainActor
@Test func deletingADeckDropsItsStudyProgress() throws {
  let (store, _, defaults) = try emptyDeckStore()
  var deck = try store.createDeck(name: "My Verbs", languageCode: "ja", answerColumnName: "en")
  deck.cards = [DeckCard(prompt: "走[はし]る", answer: "to run", languageCode: "ja")]
  try store.replace(deck)

  let study = StudyStore(deck: deck, defaults: defaults)
  study.newCardsPerDay = 5
  study.grade(.easy)
  #expect(!StudyStore(deck: deck, defaults: defaults).reviewStates.isEmpty)

  try store.delete(deck)

  let recreated = try store.createDeck(name: "My Verbs", languageCode: "ja", answerColumnName: "en")
  let reopened = StudyStore(deck: recreated, defaults: defaults)
  #expect(reopened.reviewStates.isEmpty)
  #expect(reopened.newCardsPerDay == StudyStore.defaultNewCardsPerDay)
}

@MainActor
@Test func importingNumbersTheFileWhenTheNameIsTaken() throws {
  let (store, directory, _) = try emptyDeckStore()
  let source = URL.temporaryDirectory.appending(path: "kanji-\(UUID().uuidString).csv")
  try Data("ja,en\n本[ほん],book\n".utf8).write(to: source)

  let first = try store.importDeck(from: source)
  let second = try store.importDeck(from: source)
  #expect(first.cards.count == 1)
  #expect(first.id != second.id)
  #expect(store.decks.count == 2)

  let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
  #expect(files.count == 2)
  #expect(files.filter { $0.hasSuffix("-2.csv") }.count == 1)

  let broken = URL.temporaryDirectory.appending(path: "broken-\(UUID().uuidString).csv")
  try Data("ja\n".utf8).write(to: broken)
  #expect(throws: DeckStoreError.unreadableFile(broken.lastPathComponent)) {
    _ = try store.importDeck(from: broken)
  }
}

@MainActor
@Test func speechRateIsPerDeckClampedAndPersisted() throws {
  let japanese = try CSVDeckLoader.load(name: "Japanese", data: Data("ja,en\n猫[ねこ],cat\n".utf8))
  let spanish = try CSVDeckLoader.load(name: "Spanish", data: Data("es,en\ngato,cat\n".utf8))
  let suite = "rate-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }

  let store = StudyStore(deck: japanese, defaults: defaults)
  #expect(store.speechRate == StudyStore.defaultSpeechRate)

  store.speechRate = 1.4
  #expect(StudyStore(deck: japanese, defaults: defaults).speechRate == 1.4)
  // The setting belongs to one deck only.
  #expect(StudyStore(deck: spanish, defaults: defaults).speechRate == StudyStore.defaultSpeechRate)

  store.speechRate = 9
  #expect(store.speechRate == StudyStore.speechRateRange.upperBound)
  store.speechRate = -1
  #expect(store.speechRate == StudyStore.speechRateRange.lowerBound)
}

@MainActor
@Test func browseQuestionRepeatsArePerDeckClampedAndPersisted() throws {
  let japanese = try CSVDeckLoader.load(name: "Japanese", data: Data("ja,en\n猫[ねこ],cat\n".utf8))
  let spanish = try CSVDeckLoader.load(name: "Spanish", data: Data("es,en\ngato,cat\n".utf8))
  let suite = "repeats-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }

  let store = StudyStore(deck: japanese, defaults: defaults)
  #expect(store.browseQuestionRepeats == AutoBrowse.defaultQuestionRepeats)

  store.browseQuestionRepeats = 5
  #expect(StudyStore(deck: japanese, defaults: defaults).browseQuestionRepeats == 5)
  #expect(
    StudyStore(deck: spanish, defaults: defaults).browseQuestionRepeats
      == AutoBrowse.defaultQuestionRepeats)

  store.browseQuestionRepeats = 99
  #expect(store.browseQuestionRepeats == AutoBrowse.questionRepeatsRange.upperBound)
  store.browseQuestionRepeats = 0
  #expect(store.browseQuestionRepeats == AutoBrowse.questionRepeatsRange.lowerBound)
}

@MainActor
@Test func speechRateMultiplierStaysInsideTheSupportedRange() {
  #expect(SpeechPlayer.utteranceRate(multiplier: 1) == AVSpeechUtteranceDefaultSpeechRate)
  #expect(
    SpeechPlayer.utteranceRate(multiplier: 0.5) == AVSpeechUtteranceDefaultSpeechRate / 2)
  #expect(SpeechPlayer.utteranceRate(multiplier: 2) > AVSpeechUtteranceDefaultSpeechRate)
  #expect(SpeechPlayer.utteranceRate(multiplier: 50) == AVSpeechUtteranceMaximumSpeechRate)
  #expect(SpeechPlayer.utteranceRate(multiplier: -3) == AVSpeechUtteranceMinimumSpeechRate)
}

@MainActor
@Test func deckEditorLocksStudiedCards() throws {
  let csv = "ja,en\n猫[ねこ],cat\n犬[いぬ],dog\n鳥[とり],bird\n"
  let deck = try CSVDeckLoader.load(name: "Japanese", data: Data(csv.utf8))
  let studied = deck.cards[0]
  let editor = DeckEditor(deck: deck) { $0 == studied }
  #expect(editor.lockedCount == 1)
  #expect(editor.isLocked(studied))

  #expect(throws: DeckEditor.Failure.locked) { _ = try editor.shift(from: 0, by: 1) }
  #expect(throws: DeckEditor.Failure.locked) { _ = try editor.remove(at: IndexSet(integer: 0)) }
  #expect(throws: DeckEditor.Failure.locked) {
    _ = try editor.remove(at: IndexSet([0, 1]))
  }
  #expect(throws: DeckEditor.Failure.locked) {
    _ = try editor.replace(studied, prompt: "猫[ねこ]", answer: "a cat")
  }
  #expect(throws: DeckEditor.Failure.locked) { _ = try editor.move(from: IndexSet(integer: 0), to: 3) }
}

@MainActor
@Test func deckEditorReordersAddsAndRemovesUnstudiedCards() throws {
  let csv = "ja,en\n猫[ねこ],cat\n犬[いぬ],dog\n鳥[とり],bird\n"
  let deck = try CSVDeckLoader.load(name: "Japanese", data: Data(csv.utf8))
  let editor = DeckEditor(deck: deck) { _ in false }

  #expect(try editor.shift(from: 2, by: -1).cards.map(\.prompt) == ["猫[ねこ]", "鳥[とり]", "犬[いぬ]"])
  #expect(try editor.move(from: IndexSet(integer: 0), to: 3).cards.map(\.prompt)
    == ["犬[いぬ]", "鳥[とり]", "猫[ねこ]"])
  #expect(try editor.remove(at: IndexSet([0, 2])).cards.map(\.prompt) == ["犬[いぬ]"])
  // Shifting past either end is a no-op rather than an error.
  #expect(try editor.shift(from: 0, by: -1).cards == deck.cards)

  let added = try editor.append(prompt: "  魚[さかな] ", answer: " fish ")
  #expect(added.cards.count == 4)
  #expect(added.cards[3].prompt == "魚[さかな]")
  #expect(added.cards[3].answer == "fish")

  #expect(throws: DeckEditor.Failure.empty) { _ = try editor.append(prompt: " ", answer: "fish") }
  #expect(throws: DeckEditor.Failure.duplicate) {
    _ = try editor.append(prompt: "猫[ねこ]", answer: "cat")
  }
  #expect(throws: DeckEditor.Failure.duplicate) {
    _ = try editor.replace(deck.cards[1], prompt: "猫[ねこ]", answer: "cat")
  }

  let edited = try editor.replace(deck.cards[1], prompt: "犬[いぬ]", answer: "a dog")
  #expect(edited.cards[1].answer == "a dog")
  #expect(edited.cards.count == 3)
}

@MainActor
@Test func editingKeepsProgressForUntouchedCardsOnly() throws {
  let csv = "ja,en\n猫[ねこ],cat\n犬[いぬ],dog\n鳥[とり],bird\n"
  var deck = try CSVDeckLoader.load(name: "Japanese", data: Data(csv.utf8))
  let defaults = try #require(UserDefaults(suiteName: "edit-\(UUID().uuidString)"))
  let store = StudyStore(deck: deck, defaults: defaults)

  store.grade(.easy, now: Date())
  let studied = deck.cards[0]
  #expect(store.isStudied(studied))
  #expect(!store.isStudied(deck.cards[1]))

  // Reordering the unstudied tail and dropping one card keeps the studied card's progress.
  deck.cards = [studied, deck.cards[2]]
  store.updateDeck(deck)
  #expect(store.reviewStates.count == 1)
  #expect(store.isStudied(studied))

  // Rewriting the studied card's text gives it a new identity, so its progress goes.
  deck.cards = [DeckCard(prompt: "猫[ねこ]", answer: "a cat", languageCode: "ja")]
  store.updateDeck(deck)
  #expect(store.reviewStates.isEmpty)
  #expect(StudyStore(deck: deck, defaults: defaults).reviewStates.isEmpty)
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
@Test func marksTheNewWordAndKeepsItOutOfTheTextAndSpeech() {
  let source = "俺[おれ]は**強[つよ]い**"
  #expect(FuriganaParser.parse(source) == [
    FuriganaSegment(text: "俺", reading: "おれ"),
    FuriganaSegment(text: "は"),
    FuriganaSegment(text: "強", reading: "つよ", emphasized: true),
    FuriganaSegment(text: "い", emphasized: true),
  ])
  #expect(FuriganaParser.displayText(source) == "俺は強い")
  #expect(FuriganaParser.speechText(source) == "おれはつよい")
  #expect(Romaji.transliterate(source) == "ore wa tsuyoi")

  let units = FuriganaParser.breakableUnits(source)
  #expect(units.map(\.text) == ["俺", "は", "強", "い"])
  #expect(units.map(\.emphasized) == [false, false, true, true])

  // A lone asterisk is ordinary text.
  #expect(FuriganaParser.displayText("3*4") == "3*4")
}

@MainActor
@Test func japaneseTextBreaksBetweenCharactersButLatinWordsStayWhole() {
  // A phrase with no kanji has to offer a break after every character, or it cannot wrap.
  let kana = FuriganaParser.breakableUnits("このままじゃまずいことになるぞ")
  #expect(kana.map(\.text).joined() == "このままじゃまずいことになるぞ")
  #expect(kana.allSatisfy { $0.reading == nil })
  // じゃ is one unit because a small kana may not open a line.
  #expect(kana.map(\.text) == ["こ", "の", "ま", "ま", "じゃ", "ま", "ず", "い", "こ", "と", "に", "な", "る", "ぞ"])

  // Latin script has no break between letters, and a space stays with the word before it.
  #expect(FuriganaParser.breakableUnits("por favor").map(\.text) == ["por ", "favor"])
}

@MainActor
@Test func readingsKeepTheirOkuriganaAndPunctuationOnTheSameLine() {
  // っ may not open a line, so it rides along with the reading it follows. た may, so it
  // stays a break point of its own.
  let past = FuriganaParser.breakableUnits("行[い]ったよ")
  #expect(past.map(\.text) == ["行っ", "た", "よ"])
  #expect(past[0] == FuriganaUnit(base: "行", reading: "い", trailing: "っ"))

  // Trailing punctuation never starts a line either.
  #expect(FuriganaParser.breakableUnits("食[た]べる、").map(\.text) == ["食", "べ", "る、"])
  // An opening bracket never ends one.
  #expect(FuriganaParser.breakableUnits("「あの").map(\.text) == ["「あ", "の"])

  // Splitting never changes what is shown or spoken.
  let source = "毎日[まいにち]日本語[にほんご]を勉強[べんきょう]します"
  #expect(FuriganaParser.breakableUnits(source).map(\.text).joined() == FuriganaParser.displayText(source))
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

@MainActor
private func numberedDeck(_ count: Int) throws -> Deck {
  let rows = (1...count).map { "猫[ねこ]\($0),cat \($0)" }.joined(separator: "\n")
  return try CSVDeckLoader.load(name: "Japanese", data: Data("ja,en\n\(rows)\n".utf8))
}

private let middayToday = SchedulerCalendar().startOfDay(for: Date()).addingTimeInterval(8 * 3_600)

@MainActor
@Test func leavingAndReturningToADeckChangesNoSchedule() throws {
  let csv = "ja,en\n猫[ねこ],cat\n犬[いぬ],dog\n鳥[とり],bird\n"
  let deck = try CSVDeckLoader.load(name: "Japanese", data: Data(csv.utf8))
  let suite = "revisit-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }

  let store = StudyStore(deck: deck, defaults: defaults)
  let now = Date()
  store.grade(.good, now: now)
  store.grade(.easy, now: now)
  let afterStudying = store.reviewStates

  // Opening, closing and reopening the deck, and time passing, only move the queue on.
  for offset in [60.0, 600.0, 3_600.0, 86_400.0, 8 * 86_400.0] {
    store.hideAnswer()
    store.advanceClock(to: now.addingTimeInterval(offset))
    store.revealAnswer()
    #expect(store.reviewStates == afterStudying)
  }
  #expect(StudyStore(deck: deck, defaults: defaults).reviewStates == afterStudying)
}

@MainActor
@Test func theDailyLimitResetsAtTheRolloverHourNotAtMidnight() throws {
  var utc = Calendar(identifier: .gregorian)
  utc.timeZone = try #require(TimeZone(identifier: "UTC"))
  let anki = SchedulerCalendar(rolloverHour: 4, calendar: utc)
  func at(_ day: Int, _ hour: Int) throws -> Date {
    try #require(utc.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour)))
  }

  let csv = "ja,en\n" + (1...6).map { "猫[ねこ]\($0),cat \($0)" }.joined(separator: "\n") + "\n"
  let deck = try CSVDeckLoader.load(name: "Japanese", data: Data(csv.utf8))
  let defaults = try #require(UserDefaults(suiteName: "rollover-\(UUID().uuidString)"))
  let store = StudyStore(deck: deck, defaults: defaults, calendar: anki)
  store.newCardsPerDay = 2

  store.grade(.easy, now: try at(10, 23))
  store.grade(.easy, now: try at(10, 23))
  #expect(store.counts.new == 0)
  #expect(store.isDayComplete)

  // Past midnight but before the rollover is still the same study day.
  store.advanceClock(to: try at(11, 1))
  #expect(store.counts.new == 0)
  #expect(store.isDayComplete)

  // The rollover releases the next batch.
  store.advanceClock(to: try at(11, 5))
  #expect(store.counts.new == 2)
  #expect(!store.isDayComplete)
}

@MainActor
@Test func dailyNewCardLimitHoldsBackUnseenCards() throws {
  let deck = try numberedDeck(5)
  let defaults = try #require(UserDefaults(suiteName: "limit-\(UUID().uuidString)"))
  let store = StudyStore(deck: deck, defaults: defaults)
  store.newCardsPerDay = 2

  #expect(store.dueCards.count == 2)
  #expect(store.counts == QueueCounts(new: 2, learning: 0, review: 0))

  store.grade(.easy, now: middayToday)
  store.grade(.easy, now: middayToday)
  #expect(store.currentCard == nil)
  #expect(store.counts.new == 0)
  #expect(store.isDayComplete)

  // Tomorrow releases the next batch without touching the limit.
  store.advanceClock(to: middayToday.addingTimeInterval(86_400))
  #expect(store.counts.new == 2)
  #expect(!store.isDayComplete)
}

@MainActor
@Test func countsSplitNewLearningAndReview() throws {
  let deck = try numberedDeck(4)
  let defaults = try #require(UserDefaults(suiteName: "counts-\(UUID().uuidString)"))
  let store = StudyStore(deck: deck, defaults: defaults)
  store.newCardsPerDay = 3

  store.grade(.again, now: middayToday)
  store.grade(.easy, now: middayToday)
  #expect(store.counts == QueueCounts(new: 1, learning: 1, review: 0))

  // The graduated card counts as a review only once it comes due.
  let graduated = try #require(store.reviewStates.values.first { $0.phase == .review })
  store.advanceClock(to: graduated.due)
  #expect(store.counts.review == 1)
}

@MainActor
@Test func extraCardsApplyToTodayOnly() throws {
  let deck = try numberedDeck(6)
  let defaults = try #require(UserDefaults(suiteName: "extra-\(UUID().uuidString)"))
  let store = StudyStore(deck: deck, defaults: defaults)
  store.newCardsPerDay = 1
  store.grade(.easy, now: middayToday)
  #expect(store.isDayComplete)

  store.addExtraCardsToday(2, now: middayToday)
  #expect(!store.isDayComplete)
  #expect(store.counts.new == 2)

  store.grade(.easy, now: middayToday)
  store.grade(.easy, now: middayToday)
  #expect(store.isDayComplete)

  store.advanceClock(to: middayToday.addingTimeInterval(86_400))
  #expect(store.counts.new == 1)
}

@MainActor
@Test func dayCompletionAndLimitSurviveReopeningTheDeck() throws {
  let deck = try numberedDeck(3)
  let suite = "reopen-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }

  let store = StudyStore(deck: deck, defaults: defaults)
  store.newCardsPerDay = 1
  store.grade(.easy, now: middayToday)

  let reopened = StudyStore(deck: deck, defaults: defaults)
  #expect(reopened.newCardsPerDay == 1)
  #expect(reopened.currentCard == nil)
  #expect(reopened.isDayComplete)
}

@MainActor
@Test func finishingEveryCardIsNotDayCompletion() throws {
  let deck = try numberedDeck(1)
  let defaults = try #require(UserDefaults(suiteName: "exhausted-\(UUID().uuidString)"))
  let store = StudyStore(deck: deck, defaults: defaults)

  store.grade(.easy, now: middayToday)
  #expect(store.currentCard == nil)
  #expect(!store.isDayComplete)
}

@MainActor
@Test func undoRestoresTheGradedCardOnItsAnswer() throws {
  let deck = try numberedDeck(3)
  let suite = "undo-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let store = StudyStore(deck: deck, defaults: defaults)
  let first = try #require(store.currentCard)

  #expect(!store.canUndo)
  store.grade(.easy, now: middayToday)
  #expect(store.currentCard != first)
  #expect(!store.showingAnswer)
  #expect(store.canUndo)

  store.undo()
  #expect(store.currentCard == first)
  #expect(store.showingAnswer)
  #expect(!store.isStudied(first))
  #expect(!store.canUndo)
}

@MainActor
@Test func undoWalksBackSeveralGradesAndRestoresTheDailyCount() throws {
  let deck = try numberedDeck(3)
  let suite = "undo-multi-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let store = StudyStore(deck: deck, defaults: defaults)
  store.newCardsPerDay = 2
  let first = try #require(store.currentCard)

  store.grade(.easy, now: middayToday)
  let second = try #require(store.currentCard)
  store.grade(.easy, now: middayToday)
  #expect(store.newCardsRemainingToday == 0)

  store.undo()
  #expect(store.currentCard == second)
  #expect(store.newCardsRemainingToday == 1)

  store.undo()
  #expect(store.currentCard == first)
  #expect(store.newCardsRemainingToday == 2)
  #expect(store.reviewStates.isEmpty)
}

@MainActor
@Test func undoAfterTheLastCardBringsItBack() throws {
  let deck = try numberedDeck(1)
  let suite = "undo-last-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let store = StudyStore(deck: deck, defaults: defaults)
  let only = try #require(store.currentCard)

  store.grade(.easy, now: middayToday)
  #expect(store.currentCard == nil)

  store.undo()
  #expect(store.currentCard == only)
  #expect(store.showingAnswer)
}

@MainActor
@Test func gradingAnUndoneCardAgainRepeatsScheduling() throws {
  let deck = try numberedDeck(2)
  let suite = "undo-regrade-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let store = StudyStore(deck: deck, defaults: defaults)
  let first = try #require(store.currentCard)

  store.grade(.easy, now: middayToday)
  store.undo()
  store.grade(.again, now: middayToday)

  #expect(store.reviewStates[first.id]?.phase == .learning)
  #expect(store.currentCard != first)
}

@Test func browsingWalksTheDeckInOrderThroughQuestionAndAnswer() throws {
  let csv = "ja,en\n猫[ねこ],cat\n犬[いぬ],dog\n"
  let deck = try CSVDeckLoader.load(name: "Japanese", data: Data(csv.utf8))
  var session = BrowseSession(cards: deck.cards)

  #expect(session.card == deck.cards[0])
  #expect(!session.showingAnswer)
  #expect(!session.canGoBack)

  session.forward()
  #expect(session.card == deck.cards[0])
  #expect(session.showingAnswer)

  session.forward()
  #expect(session.card == deck.cards[1])
  #expect(!session.showingAnswer)

  session.forward()
  #expect(session.showingAnswer)
  #expect(!session.canGoForward)
  session.forward()
  #expect(session.index == 1)

  session.back()
  #expect(session.card == deck.cards[1])
  #expect(!session.showingAnswer)

  session.back()
  #expect(session.card == deck.cards[0])
  #expect(!session.showingAnswer)
}

@Test func browsingRandomlyKeepsEveryCardInADifferentOrder() throws {
  let csv = "ja,en\n" + (1...20).map { "card\($0),answer\($0)\n" }.joined()
  let deck = try CSVDeckLoader.load(name: "Japanese", data: Data(csv.utf8))
  var generator = SeededGenerator(seed: 42)
  let session = BrowseSession(cards: deck.cards, using: &generator)

  #expect(session.cards.sorted { $0.id < $1.id } == deck.cards.sorted { $0.id < $1.id })
  #expect(session.cards != deck.cards)
  #expect(session.card == session.cards[0])
  #expect(!session.showingAnswer)
}

private struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed &+ 0x9e37_79b9_7f4a_7c15 }

  mutating func next() -> UInt64 {
    state = state &+ 0x9e37_79b9_7f4a_7c15
    var z = state
    z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
    z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
    return z ^ (z >> 31)
  }
}

@Test func browsingAnEmptyDeckHasNoCard() {
  var session = BrowseSession(cards: [])
  #expect(session.card == nil)
  #expect(!session.canGoForward)
  #expect(!session.canGoBack)
  session.forward()
  #expect(session.card == nil)
}

@Test func autoPlayReadsTheQuestionThreeTimesThenAlternatesWithTheAnswer() {
  let steps = AutoBrowse.steps()

  #expect(steps.prefix(3).allSatisfy { $0 == .question })
  #expect(steps.dropFirst(3) == [.answer, .question, .answer, .question, .answer, .question])
  #expect(steps.filter { $0 == .answer }.count == 3)
}

@Test func autoPlayQuestionRepeatsAreConfigurableAndClamped() {
  #expect(AutoBrowse.steps(questionRepeats: 1).prefix(2) == [.question, .answer])
  #expect(AutoBrowse.steps(questionRepeats: 5).prefix(6) == [.question, .question, .question, .question, .question, .answer])
  #expect(
    AutoBrowse.steps(questionRepeats: 0) == AutoBrowse.steps(questionRepeats: AutoBrowse.questionRepeatsRange.lowerBound))
  #expect(
    AutoBrowse.steps(questionRepeats: 99) == AutoBrowse.steps(questionRepeats: AutoBrowse.questionRepeatsRange.upperBound))
}

@Test func autoPlayAdvancesToTheNextCardAndStopsAtTheEnd() throws {
  let csv = "ja,en\n猫[ねこ],cat\n犬[いぬ],dog\n"
  let deck = try CSVDeckLoader.load(name: "Japanese", data: Data(csv.utf8))
  var session = BrowseSession(cards: deck.cards)

  session.reveal()
  #expect(session.showingAnswer)

  let movedOn = session.nextCard()
  #expect(movedOn)
  #expect(session.card == deck.cards[1])
  #expect(!session.showingAnswer)

  let movedPastTheEnd = session.nextCard()
  #expect(!movedPastTheEnd)
  #expect(session.index == 1)
}

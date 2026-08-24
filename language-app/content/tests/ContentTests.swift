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
@Test func schedulesAndAdvancesReviews() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let first = FSRSScheduler.review(nil, rating: .good, now: now)
  #expect(first.reps == 1)
  #expect(first.scheduledDays >= 1)
  #expect(first.due > now)

  let later = now.addingTimeInterval(3 * 86_400)
  let second = FSRSScheduler.review(first, rating: .easy, now: later)
  #expect(second.reps == 2)
  #expect(second.stability > first.stability)
  #expect(second.due > later)
}

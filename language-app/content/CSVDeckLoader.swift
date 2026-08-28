import Foundation

public enum CSVDeckError: LocalizedError, Equatable {
  case empty
  case missingColumns
  case invalidRow(Int)

  public var errorDescription: String? {
    switch self {
    case .empty: "The deck is empty."
    case .missingColumns: "A deck needs a language column and an answer column."
    case let .invalidRow(line): "The deck has an invalid CSV row at line \(line)."
    }
  }
}

public enum CSVDeckLoader {
  public static func load(name: String, data: Data) throws -> Deck {
    guard let text = String(data: data, encoding: .utf8) else { throw CSVDeckError.empty }
    let rows = try parse(text)
    guard let header = rows.first, !header.allSatisfy({ $0.isEmpty }) else {
      throw CSVDeckError.empty
    }
    guard header.count >= 2, !header[0].isEmpty else { throw CSVDeckError.missingColumns }

    let cards = try rows.dropFirst().enumerated().compactMap { offset, row -> DeckCard? in
      if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
        return nil
      }
      guard row.count == header.count else { throw CSVDeckError.invalidRow(offset + 2) }
      let prompt = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
      var answer = row[1...].joined(separator: " — ").trimmingCharacters(in: .whitespacesAndNewlines)
      if answer.isEmpty, Romaji.isSupported(languageCode: header[0]) {
        answer = Romaji.transliterate(prompt) ?? ""
      }
      guard !prompt.isEmpty, !answer.isEmpty else { throw CSVDeckError.invalidRow(offset + 2) }
      return DeckCard(prompt: prompt, answer: answer, languageCode: header[0])
    }

    return Deck(
      name: name,
      languageCode: header[0],
      answerColumnName: header[1],
      cards: cards
    )
  }

  private static func parse(_ text: String) throws -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var insideQuotes = false
    var index = text.startIndex

    while index < text.endIndex {
      let character = text[index]
      if character == "\"" {
        let next = text.index(after: index)
        if insideQuotes, next < text.endIndex, text[next] == "\"" {
          field.append("\"")
          index = next
        } else {
          insideQuotes.toggle()
        }
      } else if character == ",", !insideQuotes {
        row.append(field)
        field = ""
      } else if character == "\n", !insideQuotes {
        row.append(field.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
        rows.append(row)
        row = []
        field = ""
      } else {
        field.append(character)
      }
      index = text.index(after: index)
    }

    guard !insideQuotes else { throw CSVDeckError.invalidRow(rows.count + 1) }
    if !field.isEmpty || !row.isEmpty {
      row.append(field.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
      rows.append(row)
    }
    return rows
  }
}

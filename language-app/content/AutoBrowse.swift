public enum BrowseSpeechStep: Equatable, Sendable {
  case question
  case answer
}

public enum AutoBrowse {
  public static let defaultQuestionRepeats = 3
  public static let questionRepeatsRange = 1...10
  private static let alternations = 3

  public static func steps(questionRepeats: Int = defaultQuestionRepeats) -> [BrowseSpeechStep] {
    let repeats = min(
      max(questionRepeats, questionRepeatsRange.lowerBound),
      questionRepeatsRange.upperBound
    )
    return Array(repeating: BrowseSpeechStep.question, count: repeats)
      + (0..<alternations).flatMap { _ in [BrowseSpeechStep.answer, .question] }
  }
}

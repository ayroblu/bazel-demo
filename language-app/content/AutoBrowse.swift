public enum BrowseSpeechStep: Equatable, Sendable {
  case question
  case answer
}

public enum AutoBrowse {
  public static let questionRepeats = 3
  public static let alternations = 3

  public static let steps: [BrowseSpeechStep] =
    Array(repeating: BrowseSpeechStep.question, count: questionRepeats)
    + (0..<alternations).flatMap { _ in [BrowseSpeechStep.answer, .question] }
}

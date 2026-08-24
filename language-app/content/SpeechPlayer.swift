import AVFoundation

@MainActor
public final class SpeechPlayer {
  private let synthesizer = AVSpeechSynthesizer()

  public init() {}

  public func speak(_ annotatedText: String, languageCode: String) {
    synthesizer.stopSpeaking(at: .immediate)

    let utterance = AVSpeechUtterance(string: FuriganaParser.speechText(annotatedText))
    utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    utterance.volume = 1
    synthesizer.speak(utterance)
  }
}

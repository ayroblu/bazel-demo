import AVFoundation
import Observation

@MainActor
@Observable
public final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
  /// Pause between repeats of the same phrase.
  private static let repeatPause: Duration = .seconds(1)

  public private(set) var isPlaying = false

  private let synthesizer = AVSpeechSynthesizer()
  private var phrase: String?
  private var languageCode: String?
  private var repeatTask: Task<Void, Never>?

  override public init() {
    super.init()
    synthesizer.delegate = self
  }

  /// Speaks the phrase from the beginning and keeps repeating it until stopped.
  public func start(_ annotatedText: String, languageCode: String) {
    stop()
    phrase = annotatedText
    self.languageCode = languageCode
    isPlaying = true
    speakOnce()
  }

  public func stop() {
    repeatTask?.cancel()
    repeatTask = nil
    isPlaying = false
    synthesizer.stopSpeaking(at: .immediate)
  }

  public func toggle(_ annotatedText: String, languageCode: String) {
    if isPlaying {
      stop()
    } else {
      start(annotatedText, languageCode: languageCode)
    }
  }

  private func speakOnce() {
    guard let phrase, let languageCode else { return }
    let utterance = AVSpeechUtterance(string: FuriganaParser.speechText(phrase))
    utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    utterance.volume = 1
    synthesizer.speak(utterance)
  }

  private func scheduleRepeat() {
    guard isPlaying else { return }
    repeatTask?.cancel()
    repeatTask = Task { [weak self] in
      try? await Task.sleep(for: Self.repeatPause)
      guard !Task.isCancelled, let self, isPlaying else { return }
      speakOnce()
    }
  }

  public nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor [weak self] in
      self?.scheduleRepeat()
    }
  }
}

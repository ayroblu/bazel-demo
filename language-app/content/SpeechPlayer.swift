import AVFoundation
import Observation

@MainActor
@Observable
public final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
  /// Pause between repeats of the same phrase.
  private static let repeatPause: TimeInterval = 1

  public private(set) var isPlaying = false
  public let voices: VoicePreferences

  private let synthesizer = AVSpeechSynthesizer()
  private var phrase: String?
  private var languageCode: String?
  private var rate = AVSpeechUtteranceDefaultSpeechRate
  private var repeatWork: DispatchWorkItem?
  private var repeats = true
  private var completion: (() -> Void)?

  public init(voices: VoicePreferences = VoicePreferences()) {
    self.voices = voices
    super.init()
    synthesizer.delegate = self
  }

  /// Speaks the phrase from the beginning and keeps repeating it until stopped.
  /// The rate is a multiple of the system's default speaking rate.
  public func start(_ annotatedText: String, languageCode: String, rate multiplier: Double = 1) {
    stop()
    activateAudioSession()
    phrase = annotatedText
    self.languageCode = languageCode
    rate = Self.utteranceRate(multiplier: multiplier)
    repeats = true
    isPlaying = true
    speak()
  }

  /// Speaks the phrase once and calls back after the same pause a repeat would take.
  public func speakOnce(
    _ annotatedText: String,
    languageCode: String,
    rate multiplier: Double = 1,
    completion: @escaping () -> Void
  ) {
    stop()
    activateAudioSession()
    phrase = annotatedText
    self.languageCode = languageCode
    rate = Self.utteranceRate(multiplier: multiplier)
    repeats = false
    self.completion = completion
    isPlaying = true
    speak()
  }

  /// Maps a multiplier onto the range AVSpeechUtterance accepts.
  public static func utteranceRate(multiplier: Double) -> Float {
    let scaled = Float(multiplier) * AVSpeechUtteranceDefaultSpeechRate
    return min(
      max(scaled, AVSpeechUtteranceMinimumSpeechRate),
      AVSpeechUtteranceMaximumSpeechRate
    )
  }

  public func stop() {
    repeatWork?.cancel()
    repeatWork = nil
    repeats = true
    completion = nil
    isPlaying = false
    synthesizer.stopSpeaking(at: .immediate)
    deactivateAudioSession()
  }

  public func toggle(_ annotatedText: String, languageCode: String, rate multiplier: Double = 1) {
    if isPlaying {
      stop()
    } else {
      start(annotatedText, languageCode: languageCode, rate: multiplier)
    }
  }

  /// Without an explicit playback category iOS uses the ambient category, which the
  /// Ring/Silent switch mutes. The simulator has no such switch, so this only shows on device.
  private func activateAudioSession() {
    #if os(iOS)
      let session = AVAudioSession.sharedInstance()
      try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
      try? session.setActive(true)
    #endif
  }

  private func deactivateAudioSession() {
    #if os(iOS)
      try? AVAudioSession.sharedInstance().setActive(
        false, options: .notifyOthersOnDeactivation)
    #endif
  }

  private func speak() {
    guard let phrase, let languageCode else { return }
    let utterance = AVSpeechUtterance(string: FuriganaParser.speechText(phrase))
    utterance.voice = voices.voice(for: languageCode) ?? AVSpeechSynthesisVoice(language: languageCode)
    utterance.rate = rate
    utterance.volume = 1
    synthesizer.speak(utterance)
  }

  /// Repeats are scheduled on the main run loop rather than in a Task, so speech
  /// synthesis is never started from a Swift concurrency thread.
  private func scheduleNext() {
    guard isPlaying else { return }
    repeatWork?.cancel()
    let repeats = repeats
    let work = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.isPlaying else { return }
        if repeats {
          self.speak()
        } else {
          let completion = self.completion
          self.completion = nil
          self.isPlaying = false
          completion?()
        }
      }
    }
    repeatWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.repeatPause, execute: work)
  }

  public nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        self?.scheduleNext()
      }
    }
  }
}

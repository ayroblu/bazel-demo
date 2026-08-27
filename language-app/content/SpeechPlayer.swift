import AVFoundation
import Observation

#if os(iOS)
  import MediaPlayer
#endif

@MainActor
@Observable
public final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
  /// Pause between repeats of the same phrase.
  private static let repeatPause: TimeInterval = 1

  public private(set) var isPlaying = false
  public let voices: VoicePreferences
  /// Invoked when the lock screen or Control Center asks for playback to resume or stop.
  public var onRemotePlay: (() -> Void)?
  public var onRemotePause: (() -> Void)?

  private let synthesizer = AVSpeechSynthesizer()
  private var phrase: String?
  private var languageCode: String?
  private var rate = AVSpeechUtteranceDefaultSpeechRate
  private var repeats = true
  private var completion: (() -> Void)?
  /// True between the first utterance of a run and the run being stopped, so the pause
  /// only applies between phrases and never before the first one.
  private var continuing = false
  private var remoteCommandsConfigured = false

  public init(voices: VoicePreferences = VoicePreferences()) {
    self.voices = voices
    super.init()
    synthesizer.delegate = self
  }

  /// Speaks the phrase from the beginning and keeps repeating it until stopped.
  /// The rate is a multiple of the system's default speaking rate.
  public func start(_ annotatedText: String, languageCode: String, rate multiplier: Double = 1) {
    halt()
    activateAudioSession()
    phrase = annotatedText
    self.languageCode = languageCode
    rate = Self.utteranceRate(multiplier: multiplier)
    repeats = true
    continuing = false
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
    halt()
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
    halt()
    continuing = false
    clearNowPlaying()
    deactivateAudioSession()
  }

  /// Stops the current phrase but keeps the audio session, so a run of phrases holds
  /// onto background audio instead of handing it back between each one.
  private func halt() {
    repeats = true
    completion = nil
    isPlaying = false
    synthesizer.stopSpeaking(at: .immediate)
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
      configureRemoteCommands()
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
    // The synthesizer owns the pause. A timer gap would leave the app playing nothing,
    // which iOS treats as finished audio and suspends once the screen locks.
    utterance.preUtteranceDelay = continuing ? Self.repeatPause : 0
    continuing = true
    updateNowPlaying(FuriganaParser.displayText(phrase))
    synthesizer.speak(utterance)
  }

  /// Continuations run on the main run loop rather than in a Task, so speech
  /// synthesis is never started from a Swift concurrency thread.
  private func scheduleNext() {
    guard isPlaying else { return }
    if repeats {
      speak()
    } else {
      let completion = self.completion
      self.completion = nil
      isPlaying = false
      completion?()
    }
  }

  private func updateNowPlaying(_ title: String) {
    #if os(iOS)
      MPNowPlayingInfoCenter.default().nowPlayingInfo = [
        MPMediaItemPropertyTitle: title,
        MPNowPlayingInfoPropertyPlaybackRate: 1.0,
      ]
    #endif
  }

  private func clearNowPlaying() {
    #if os(iOS)
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    #endif
  }

  /// Lock screen and Control Center buttons, so the controls iOS shows for background
  /// audio actually drive playback instead of sitting dead.
  private func configureRemoteCommands() {
    #if os(iOS)
      guard !remoteCommandsConfigured else { return }
      remoteCommandsConfigured = true
      let center = MPRemoteCommandCenter.shared()
      center.playCommand.addTarget { [weak self] _ in
        self?.handleRemote(.play)
        return .success
      }
      center.pauseCommand.addTarget { [weak self] _ in
        self?.handleRemote(.pause)
        return .success
      }
      center.togglePlayPauseCommand.addTarget { [weak self] _ in
        self?.handleRemote(.toggle)
        return .success
      }
    #endif
  }

  private enum RemoteCommand: Sendable {
    case play
    case pause
    case toggle
  }

  private nonisolated func handleRemote(_ command: RemoteCommand) {
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        switch command {
        case .play: self.onRemotePlay?()
        case .pause: self.remotePause()
        case .toggle: self.isPlaying ? self.remotePause() : self.onRemotePlay?()
        }
      }
    }
  }

  private func remotePause() {
    if let onRemotePause {
      onRemotePause()
    } else {
      stop()
    }
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

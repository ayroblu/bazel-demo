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

  /// One phrase being read, however many times.
  private struct Run {
    let phrase: String
    let languageCode: String
    let rate: Float
    /// Readings still to be heard, or nil while the phrase repeats until stopped.
    var remaining: Int?
    let completion: (() -> Void)?
  }

  /// Shared and never released: TextToSpeech crashes if a synthesizer is deallocated
  /// while it still has speech in flight.
  private nonisolated(unsafe) static let synthesizer = AVSpeechSynthesizer()
  private var synthesizer: AVSpeechSynthesizer { Self.synthesizer }
  private var run: Run?
  /// True between the first utterance of a run and the run being stopped, so the pause
  /// only applies between phrases and never before the first one.
  private var continuing = false
  private var remoteCommandsConfigured = false

  /// The synthesizer is shared, so its delegate is claimed when speaking rather than here:
  /// a player built while another one is mid phrase must not take its callbacks. SwiftUI
  /// builds a player every time it re-creates a view that holds one.
  public init(voices: VoicePreferences = VoicePreferences()) {
    self.voices = voices
    super.init()
  }

  deinit {
    let synthesizer = Self.synthesizer
    guard synthesizer.delegate === self else { return }
    synthesizer.delegate = nil
    synthesizer.stopSpeaking(at: .immediate)
  }

  /// Speaks the phrase from the beginning, `times` in a row, or until stopped when `times`
  /// is nil. The rate is a multiple of the system's default speaking rate.
  public func start(
    _ annotatedText: String,
    languageCode: String,
    rate multiplier: Double = 1,
    times: Int? = nil
  ) {
    halt()
    continuing = false
    begin(
      Run(
        phrase: annotatedText,
        languageCode: languageCode,
        rate: Self.utteranceRate(multiplier: multiplier),
        remaining: times.map { max(1, $0) },
        completion: nil
      ))
  }

  /// Speaks the phrase once and calls back after the same pause a repeat would take.
  public func speakOnce(
    _ annotatedText: String,
    languageCode: String,
    rate multiplier: Double = 1,
    completion: @escaping () -> Void
  ) {
    halt()
    begin(
      Run(
        phrase: annotatedText,
        languageCode: languageCode,
        rate: Self.utteranceRate(multiplier: multiplier),
        remaining: 1,
        completion: completion
      ))
  }

  public func toggle(
    _ annotatedText: String,
    languageCode: String,
    rate multiplier: Double = 1,
    times: Int? = nil
  ) {
    if isPlaying {
      stop()
    } else {
      start(annotatedText, languageCode: languageCode, rate: multiplier, times: times)
    }
  }

  public func stop() {
    halt()
    continuing = false
    clearNowPlaying()
    deactivateAudioSession()
  }

  /// Maps a multiplier onto the range AVSpeechUtterance accepts.
  public static func utteranceRate(multiplier: Double) -> Float {
    let scaled = Float(multiplier) * AVSpeechUtteranceDefaultSpeechRate
    return min(
      max(scaled, AVSpeechUtteranceMinimumSpeechRate),
      AVSpeechUtteranceMaximumSpeechRate
    )
  }

  // MARK: - Running a phrase

  private func begin(_ run: Run) {
    activateAudioSession()
    self.run = run
    isPlaying = true
    speak(run.remaining ?? 1)
  }

  /// Drops the current run but keeps the audio session, so a run of phrases holds onto
  /// background audio instead of handing it back between each one.
  private func halt() {
    run = nil
    isPlaying = false
    synthesizer.stopSpeaking(at: .immediate)
  }

  /// Hands the readings to the synthesizer in one go, each one waiting out the pause before
  /// it speaks. The synthesizer plays them back to back, so nothing has to be scheduled while
  /// the phrase is being read.
  private func speak(_ count: Int) {
    guard let run else { return }
    synthesizer.delegate = self
    updateNowPlaying(FuriganaParser.displayText(run.phrase))
    for _ in 0..<count {
      let utterance = AVSpeechUtterance(string: FuriganaParser.speechText(run.phrase))
      utterance.voice = utteranceVoice(for: run)
      utterance.rate = run.rate
      utterance.volume = 1
      // The synthesizer owns the pause. A timer gap would leave the app playing nothing,
      // which iOS treats as finished audio and suspends once the screen locks.
      utterance.preUtteranceDelay = continuing ? Self.repeatPause : 0
      continuing = true
      synthesizer.speak(utterance)
    }
  }

  private func utteranceVoice(for run: Run) -> AVSpeechSynthesisVoice? {
    voices.voice(for: run.languageCode) ?? AVSpeechSynthesisVoice(language: run.languageCode)
  }

  /// Counts off a reading as it ends and closes the run after the last one. A run that was
  /// stopped left no run behind, so its late callbacks do nothing.
  private func readingFinished() {
    guard var run else { return }
    // An endless run is the one case that still has to queue as it goes.
    guard let left = run.remaining else { return speak(1) }
    guard left > 1 else { return finish() }
    run.remaining = left - 1
    self.run = run
  }

  private func finish() {
    let completion = run?.completion
    run = nil
    isPlaying = false
    // A run that nothing is waiting on has finished with the audio, unlike one whose
    // completion goes straight on to the next phrase.
    if completion == nil {
      continuing = false
      clearNowPlaying()
      deactivateAudioSession()
    }
    completion?()
  }

  // MARK: - Audio session and remote controls

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
    Task { @MainActor [weak self] in
      guard let self else { return }
      switch command {
      case .play: onRemotePlay?()
      case .pause: remotePause()
      case .toggle: isPlaying ? remotePause() : onRemotePlay?()
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

  // MARK: - AVSpeechSynthesizerDelegate

  public nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor [weak self] in
      self?.readingFinished()
    }
  }
}

import AVFoundation

@MainActor
public enum VoiceCatalog {
  /// Eloquence voices are deliberately synthetic novelty voices, so they rank last.
  private static let noveltyPrefix = "com.apple.eloquence."

  private static var cachedVoices: [AVSpeechSynthesisVoice]?
  private static var voiceChangeObserver: NSObjectProtocol?

  /// Reading the installed voices hits the system voice database, so the result is cached
  /// until the system reports that the installed voices changed.
  private static var installedVoices: [AVSpeechSynthesisVoice] {
    if let cachedVoices { return cachedVoices }
    observeVoiceChanges()
    let voices = AVSpeechSynthesisVoice.speechVoices()
    cachedVoices = voices
    return voices
  }

  private static func observeVoiceChanges() {
    guard voiceChangeObserver == nil else { return }
    voiceChangeObserver = NotificationCenter.default.addObserver(
      forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
      object: nil,
      queue: .main
    ) { _ in
      MainActor.assumeIsolated { cachedVoices = nil }
    }
  }

  /// Voices that can speak the language, best sounding first.
  public static func voices(
    for languageCode: String,
    preferring gender: AVSpeechSynthesisVoiceGender = .male
  ) -> [AVSpeechSynthesisVoice] {
    installedVoices
      .filter { matches(voice: $0, languageCode: languageCode) }
      .sorted { left, right in
        let leftRank = rank(left, gender: gender)
        let rightRank = rank(right, gender: gender)
        return leftRank == rightRank ? left.name < right.name : leftRank > rightRank
      }
  }

  public static func preferred(
    for languageCode: String,
    gender: AVSpeechSynthesisVoiceGender = .male
  ) -> AVSpeechSynthesisVoice? {
    voices(for: languageCode, preferring: gender).first
  }

  public static func voice(withIdentifier identifier: String) -> AVSpeechSynthesisVoice? {
    installedVoices.first { $0.identifier == identifier }
  }

  public static func qualityLabel(_ voice: AVSpeechSynthesisVoice) -> String {
    switch voice.quality {
    case .premium: "Premium"
    case .enhanced: "Enhanced"
    default: voice.identifier.hasPrefix(noveltyPrefix) ? "Novelty" : "Compact"
    }
  }

  public static func genderLabel(_ voice: AVSpeechSynthesisVoice) -> String? {
    switch voice.gender {
    case .male: "Male"
    case .female: "Female"
    default: nil
    }
  }

  public static func describe(_ voice: AVSpeechSynthesisVoice) -> String {
    [voice.name, genderLabel(voice), qualityLabel(voice)]
      .compactMap { $0 }
      .joined(separator: " · ")
  }

  private static func matches(voice: AVSpeechSynthesisVoice, languageCode: String) -> Bool {
    let wanted = languageCode.lowercased()
    let language = voice.language.lowercased()
    return language == wanted || language.hasPrefix(wanted + "-")
  }

  /// Higher is better: quality dominates, then the requested gender, then real over novelty voices.
  private static func rank(
    _ voice: AVSpeechSynthesisVoice,
    gender: AVSpeechSynthesisVoiceGender
  ) -> Int {
    var score = 0
    switch voice.quality {
    case .premium: score += 400
    case .enhanced: score += 300
    default: score += 100
    }
    if voice.gender == gender { score += 40 }
    if !voice.identifier.hasPrefix(noveltyPrefix) { score += 20 }
    return score
  }
}

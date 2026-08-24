import AVFoundation
import Observation

/// Remembers the chosen voice per language, falling back to the best sounding male voice.
@MainActor
@Observable
public final class VoicePreferences {
  private let defaults: UserDefaults
  private var selections: [String: String]

  private static let key = "language-app.voices.v1"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    selections = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
  }

  public func selectedIdentifier(for languageCode: String) -> String? {
    selections[languageCode]
  }

  public func select(_ identifier: String?, for languageCode: String) {
    if let identifier {
      selections[languageCode] = identifier
    } else {
      selections.removeValue(forKey: languageCode)
    }
    defaults.set(selections, forKey: Self.key)
  }

  public func voice(for languageCode: String) -> AVSpeechSynthesisVoice? {
    if let identifier = selections[languageCode],
      let voice = VoiceCatalog.voice(withIdentifier: identifier)
    {
      return voice
    }
    return VoiceCatalog.preferred(for: languageCode)
  }
}

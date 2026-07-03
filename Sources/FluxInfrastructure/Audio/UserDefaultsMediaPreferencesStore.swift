import Foundation
import FluxDomain

/// Persiste as preferências de mídia em UserDefaults (valores simples, sem
/// segredo — docs/05). Chave ausente assume o padrão comercial, então uma
/// instalação existente ganha eco/ruído tratados sem migração.
public struct UserDefaultsMediaPreferencesStore: MediaPreferencesStoreProtocol {
    private static let codecKey = "media.preferredCodec"
    private static let echoCancellationKey = "media.echoCancellationEnabled"
    /// Chave da era em que eco+ruído eram um toggle só — lida como fallback
    /// para quem gravou preferência antes da separação.
    private static let legacyVoiceProcessingKey = "media.voiceProcessingEnabled"
    private static let silenceSuppressionKey = "media.silenceSuppressionEnabled"
    private static let autoGainKey = "media.autoGainControlEnabled"

    /// Suite isolada nos testes; `nil` = standard do app.
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func load() -> MediaPreferences {
        let defaults = defaults
        var preferences = MediaPreferences.standard
        if let raw = defaults.string(forKey: Self.codecKey),
           let codec = AudioCodecPreference(rawValue: raw) {
            preferences.preferredCodec = codec
        }
        if defaults.object(forKey: Self.echoCancellationKey) != nil {
            preferences.echoCancellationEnabled = defaults.bool(forKey: Self.echoCancellationKey)
        } else if defaults.object(forKey: Self.legacyVoiceProcessingKey) != nil {
            preferences.echoCancellationEnabled = defaults.bool(forKey: Self.legacyVoiceProcessingKey)
        }
        if defaults.object(forKey: Self.silenceSuppressionKey) != nil {
            preferences.silenceSuppressionEnabled = defaults.bool(forKey: Self.silenceSuppressionKey)
        }
        if defaults.object(forKey: Self.autoGainKey) != nil {
            preferences.autoGainControlEnabled = defaults.bool(forKey: Self.autoGainKey)
        }
        return preferences
    }

    public func save(_ preferences: MediaPreferences) {
        let defaults = defaults
        defaults.set(preferences.preferredCodec.rawValue, forKey: Self.codecKey)
        defaults.set(preferences.echoCancellationEnabled, forKey: Self.echoCancellationKey)
        defaults.set(preferences.silenceSuppressionEnabled, forKey: Self.silenceSuppressionKey)
        defaults.set(preferences.autoGainControlEnabled, forKey: Self.autoGainKey)
    }
}

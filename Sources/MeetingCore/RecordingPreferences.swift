import Foundation

public enum RecordingPreferences {
    public static let automaticTranscriptionKey = "automaticTranscription"

    /// Missing preference intentionally means recording only, never automatic inference.
    public static func automaticTranscription(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: automaticTranscriptionKey)
    }

    public static func setAutomaticTranscription(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: automaticTranscriptionKey)
    }
}

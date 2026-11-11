import Foundation

public enum RecordingPreferences {
    public static let automaticTranscriptionKey = "automaticTranscription"
    public static let askForRecordingNameKey = "askForRecordingName"

    public static func askForRecordingName(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: askForRecordingNameKey) == nil || defaults.bool(forKey: askForRecordingNameKey)
    }

    public static func setAskForRecordingName(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: askForRecordingNameKey)
    }

    /// Missing preference intentionally means recording only, never automatic inference.
    public static func automaticTranscription(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: automaticTranscriptionKey)
    }

    public static func setAutomaticTranscription(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: automaticTranscriptionKey)
    }
}

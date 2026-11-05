import Foundation

public enum LibraryPreferences {
    private static let rootKey = "meetingLibraryPath"
    private static let setupKey = "onboardingCompleted"
    private static let textRootKey = "transcriptLibraryPath"

    public static func suggestedRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Mantis", isDirectory: true)
    }

    public static func initialRoot(defaults: UserDefaults = .standard,
                                   home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                   applicationSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) -> URL {
        if let path = defaults.string(forKey: rootKey), path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let legacy = applicationSupport.appendingPathComponent("MeetingRecorder/Meetings", isDirectory: true)
        // Keep existing recordings visible until the user explicitly copies the library.
        if FileManager.default.fileExists(atPath: legacy.path) {
            do {
                let entries = try FileManager.default.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)
                if entries.contains(where: {
                    UUID(uuidString: $0.lastPathComponent) != nil || $0.lastPathComponent == ".mantis"
                }) { return legacy }
            } catch {
                // A read failure must be reported by MeetingStore, not silently switch libraries.
                return legacy
            }
        }
        return suggestedRoot(home: home)
    }

    public static func setRoot(_ root: URL, defaults: UserDefaults = .standard) {
        defaults.set(root.standardizedFileURL.path, forKey: rootKey)
    }

    public static func transcriptRoot(defaults: UserDefaults = .standard) -> URL? {
        guard let path = defaults.string(forKey: textRootKey), path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public static func setTranscriptRoot(_ root: URL?, defaults: UserDefaults = .standard) {
        if let root { defaults.set(root.standardizedFileURL.path, forKey: textRootKey) }
        else { defaults.removeObject(forKey: textRootKey) }
    }

    public static func setupCompleted(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: setupKey)
    }

    public static func completeSetup(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: setupKey)
    }
}

import Foundation

public enum LaunchPreferences {
    public static let startInMenuBarKey = "startInMenuBar"

    public static func startsWithoutWindow(defaults: UserDefaults = .standard,
                                           arguments: [String] = Array(CommandLine.arguments.dropFirst())) -> Bool {
        // Keep initial setup accessible even if a preference survives a reinstall.
        let isRecordingControl = arguments == ["--toggle-recording"] || arguments == ["--stop-recording"]
            || arguments == ["--cancel-transcription"]
        return LibraryPreferences.setupCompleted(defaults: defaults)
            && (isRecordingControl || (arguments != ["--show"] && defaults.bool(forKey: startInMenuBarKey)))
    }
}

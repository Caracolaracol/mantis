import Foundation

public enum LaunchPreferences {
    public static let startInMenuBarKey = "startInMenuBar"

    public static func startsWithoutWindow(defaults: UserDefaults = .standard) -> Bool {
        // Keep initial setup accessible even if a preference survives a reinstall.
        defaults.bool(forKey: startInMenuBarKey) && LibraryPreferences.setupCompleted(defaults: defaults)
    }
}

import MeetingCore
import XCTest

final class LaunchPreferencesTests: XCTestCase {
    func testMenuBarLaunchIsOptInAndRequiresCompletedSetup() throws {
        let name = "LaunchPreferencesTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(LaunchPreferences.startsWithoutWindow(defaults: defaults))
        defaults.set(true, forKey: LaunchPreferences.startInMenuBarKey)
        XCTAssertFalse(LaunchPreferences.startsWithoutWindow(defaults: defaults))
        LibraryPreferences.completeSetup(defaults: defaults)
        XCTAssertTrue(LaunchPreferences.startsWithoutWindow(defaults: defaults))
        defaults.set(false, forKey: LaunchPreferences.startInMenuBarKey)
        XCTAssertFalse(LaunchPreferences.startsWithoutWindow(defaults: defaults))
    }

    func testQuickRecordingColdLaunchSuppressesLibraryRegardlessOfPreference() throws {
        let name = "LaunchControlTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        for command in ["--toggle-recording", "--stop-recording", "--cancel-transcription"] {
            XCTAssertFalse(LaunchPreferences.startsWithoutWindow(defaults: defaults, arguments: [command]))
        }
        LibraryPreferences.completeSetup(defaults: defaults)
        for command in ["--toggle-recording", "--stop-recording", "--cancel-transcription"] {
            XCTAssertTrue(LaunchPreferences.startsWithoutWindow(defaults: defaults, arguments: [command]))
        }
        XCTAssertFalse(LaunchPreferences.startsWithoutWindow(defaults: defaults, arguments: []))
        defaults.set(true, forKey: LaunchPreferences.startInMenuBarKey)
        XCTAssertFalse(LaunchPreferences.startsWithoutWindow(defaults: defaults, arguments: ["--show"]))
    }
}

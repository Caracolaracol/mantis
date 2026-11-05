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
}

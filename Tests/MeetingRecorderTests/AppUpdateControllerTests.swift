import XCTest
import MeetingCore
@testable import MeetingRecorder

@MainActor
final class AppUpdateControllerTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "AppUpdateControllerTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testAutomaticChecksAreOptInAndPreviewDoesNotReadOrWritePreferences() async {
        let defaults = defaults()
        var calls = 0
        let controller = AppUpdateController(defaults: defaults, installedVersion: "0.3.0", fetch: { calls += 1; return nil })
        XCTAssertFalse(controller.automaticChecks)
        await controller.check(automatically: true)
        XCTAssertEqual(calls, 0)
        defaults.set(true, forKey: AppUpdateController.automaticKey)
        let preview = AppUpdateController(defaults: defaults, persists: false, installedVersion: "0.3.0", fetch: { calls += 1; return nil })
        XCTAssertFalse(preview.automaticChecks)
        preview.automaticChecks = false
        XCTAssertTrue(defaults.bool(forKey: AppUpdateController.automaticKey))
        XCTAssertNil(defaults.object(forKey: AppUpdateController.lastAttemptKey))
    }

    func testAutomaticAttemptsAreLimitedToOnceDailyAcrossRelaunches() async {
        let defaults = defaults()
        var date = Date(timeIntervalSince1970: 1_000_000)
        var calls = 0
        let fetch: () async throws -> AppRelease? = { calls += 1; return AppRelease(tag: "v0.4.0") }
        let controller = AppUpdateController(defaults: defaults, installedVersion: "0.3.0", now: { date }, fetch: fetch)
        controller.automaticChecks = true
        await controller.check(automatically: true)
        await controller.check(automatically: true)
        XCTAssertEqual(calls, 1)
        let relaunched = AppUpdateController(defaults: defaults, installedVersion: "0.3.0", now: { date }, fetch: fetch)
        await relaunched.check(automatically: true)
        XCTAssertEqual(calls, 1)
        date = date.addingTimeInterval(24 * 60 * 60)
        await relaunched.check(automatically: true)
        XCTAssertEqual(calls, 2)
    }

    func testManualCheckBypassesOptInCooldownAndSkippedVersion() async throws {
        let defaults = defaults()
        let release = try XCTUnwrap(AppRelease(tag: "v0.4.0"))
        var calls = 0
        let controller = AppUpdateController(defaults: defaults, installedVersion: "0.3.0", fetch: { calls += 1; return release })
        await controller.check()
        XCTAssertEqual(controller.state, .available(release))
        controller.skip(release)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(defaults.string(forKey: AppUpdateController.skippedKey), "0.4.0")
        await controller.check()
        XCTAssertEqual(controller.state, .available(release))
        XCTAssertEqual(calls, 2)
    }

    func testSkippedVersionRemainsSkippedAfterRestartButNewerReleaseIsOffered() async throws {
        let defaults = defaults()
        defaults.set("0.4.0", forKey: AppUpdateController.skippedKey)
        defaults.set(true, forKey: AppUpdateController.automaticKey)
        var release = AppRelease(tag: "v0.4.0")
        var date = Date()
        let controller = AppUpdateController(defaults: defaults, installedVersion: "0.3.0", now: { date }, fetch: { release })
        await controller.check(automatically: true)
        XCTAssertEqual(controller.state, .idle)
        release = AppRelease(tag: "v0.5.0")
        date = date.addingTimeInterval(AppUpdateController.interval)
        await controller.check(automatically: true)
        XCTAssertEqual(controller.state, .available(try XCTUnwrap(release)))
    }

    func testNoDowngradesAndNoUpdateIsReportedForEqualOrMissingRelease() async {
        for tag in ["v0.2.0", "v0.3.0", "invalid"] {
            let controller = AppUpdateController(defaults: defaults(), installedVersion: "0.3.0", fetch: { AppRelease(tag: tag) })
            await controller.check()
            XCTAssertEqual(controller.state, .upToDate)
        }
    }

    func testBusyChecksNeverFetchAndInvalidInstalledVersionFailsClosed() async {
        var calls = 0
        let controller = AppUpdateController(defaults: defaults(), installedVersion: "0.3.0", fetch: { calls += 1; return nil })
        controller.automaticChecks = true
        await controller.check(isBusy: true)
        await controller.check(automatically: true, isBusy: true)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(controller.state, .idle)
        let invalid = AppUpdateController(defaults: defaults(), installedVersion: "invalid", fetch: { calls += 1; return nil })
        await invalid.check()
        XCTAssertEqual(calls, 0)
    }

    func testAutomaticErrorsAreSilentAndThrottledButManualErrorsAreVisible() async {
        var calls = 0
        let controller = AppUpdateController(defaults: defaults(), installedVersion: "0.3.0", fetch: { calls += 1; throw AppUpdateError.unavailable })
        controller.automaticChecks = true
        await controller.check(automatically: true)
        XCTAssertEqual(controller.state, .idle)
        await controller.check(automatically: true)
        XCTAssertEqual(calls, 1)
        await controller.check()
        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(calls, 2)
    }

    func testConcurrentChecksAreDeduplicatedAndDisablingSuppressesInflightAutomaticResult() async {
        var continuation: CheckedContinuation<AppRelease?, Error>?
        var calls = 0
        let controller = AppUpdateController(defaults: defaults(), installedVersion: "0.3.0", fetch: {
            calls += 1
            return try await withCheckedThrowingContinuation { continuation = $0 }
        })
        controller.automaticChecks = true
        let pending = Task { await controller.check(automatically: true) }
        while continuation == nil { await Task.yield() }
        XCTAssertTrue(controller.isChecking)
        await controller.check()
        XCTAssertEqual(calls, 1)
        controller.automaticChecks = false
        continuation?.resume(returning: AppRelease(tag: "v0.4.0"))
        await pending.value
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.isChecking)
    }

    func testLaterDoesNotPermanentlySkipRelease() async {
        let defaults = defaults()
        let controller = AppUpdateController(defaults: defaults, installedVersion: "0.3.0", fetch: { AppRelease(tag: "v0.4.0") })
        await controller.check()
        controller.dismiss()
        XCTAssertNil(defaults.string(forKey: AppUpdateController.skippedKey))
        XCTAssertEqual(controller.state, .idle)
    }

    func testWithdrawnReleaseClearsAnOldNoticeOnSuccessfulAutomaticCheck() async {
        var release = AppRelease(tag: "v0.4.0")
        var date = Date()
        let controller = AppUpdateController(defaults: defaults(), installedVersion: "0.3.0", now: { date }, fetch: { release })
        controller.automaticChecks = true
        await controller.check(automatically: true)
        XCTAssertEqual(controller.state, .available(release!))
        release = nil
        date = date.addingTimeInterval(AppUpdateController.interval)
        await controller.check(automatically: true)
        XCTAssertEqual(controller.state, .idle)
    }
}

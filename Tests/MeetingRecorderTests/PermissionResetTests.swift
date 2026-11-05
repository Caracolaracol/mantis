import XCTest
@testable import MeetingRecorder

final class PermissionResetTests: XCTestCase {
    func testResetCommandIsRestrictedToMantisScreenCapture() async throws {
        try await SystemAudioPermissionReset.reset { executable, arguments in
            XCTAssertEqual(executable.path, "/usr/bin/tccutil")
            XCTAssertEqual(arguments, ["reset", "ScreenCapture", "local.agus.MeetingRecorder"])
            return .init(status: 0, output: "Synthetic success")
        }
    }

    func testNonzeroExitReportsFailure() async {
        do {
            try await SystemAudioPermissionReset.reset { _, _ in .init(status: 1, output: "Synthetic denial") }
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Synthetic denial")
        }
    }

    func testProcessLaunchErrorIsReported() async {
        do {
            try await SystemAudioPermissionReset.reset { _, _ in
                throw NSError(domain: "SyntheticLaunchError", code: 2)
            }
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual((error as NSError).domain, "SyntheticLaunchError")
        }
    }

    @MainActor
    func testSuccessfulResetRequiresRestartAndPreservesMicrophone() async {
        let model = AppModel(preview: true)
        let microphone = model.permissionSnapshot.microphone
        XCTAssertEqual(model.systemAudioPermissionResetState, .idle)
        await model.resetSystemAudioPermission {
            await MainActor.run {
                XCTAssertTrue(model.busy)
                XCTAssertEqual(model.systemAudioPermissionResetState, .running)
            }
            // A repeated action must not launch another command while running.
            await model.resetSystemAudioPermission { XCTFail("Duplicate reset must not run") }
        }
        XCTAssertEqual(model.systemAudioPermissionResetState, .requiresRestart)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.permissionSnapshot.microphone, microphone)
        XCTAssertEqual(model.permissionSnapshot.systemAudio, .unverified)
        XCTAssertNotNil(model.permissionSetupMessage)
        await model.resetSystemAudioPermission { XCTFail("Must restart before resetting again") }
    }

    @MainActor
    func testFailureDoesNotClaimSuccessAndAllowsRetry() async {
        let model = AppModel(preview: true)
        let snapshot = model.permissionSnapshot
        await model.resetSystemAudioPermission {
            throw NSError(domain: "SyntheticResetFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: "Synthetic failure"])
        }
        XCTAssertEqual(model.systemAudioPermissionResetState, .failed("Synthetic failure"))
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.permissionSnapshot, snapshot)
        await model.resetSystemAudioPermission {}
        XCTAssertEqual(model.systemAudioPermissionResetState, .requiresRestart)
    }
}

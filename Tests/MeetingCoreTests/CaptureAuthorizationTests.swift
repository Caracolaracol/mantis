import XCTest
import MeetingCore

final class CaptureAuthorizationTests: XCTestCase {
    func testFalsePreflightDoesNotClaimPermissionWasNeverGranted() {
        XCTAssertEqual(CaptureAuthorizationState.screenCapturePreflight(true), .allowed)
        XCTAssertEqual(CaptureAuthorizationState.screenCapturePreflight(false), .unverified)
        XCTAssertNotEqual(CaptureAuthorizationState.screenCapturePreflight(false), .notRequested)
        XCTAssertNotEqual(CaptureAuthorizationState.screenCapturePreflight(false), .denied)
    }

    func testOnlyRequiredPermissionsAreShown() {
        let snapshot = CaptureAuthorizationSnapshot(microphone: .denied, systemAudio: .allowed)
        XCTAssertEqual(snapshot.required(for: .systemAudio), [.systemAudio])
        XCTAssertEqual(snapshot.required(for: .microphone), [.microphone])
        XCTAssertEqual(snapshot.required(for: .systemAndMicrophone), [.microphone, .systemAudio])
        XCTAssertEqual(snapshot[.microphone], .denied)
        XCTAssertEqual(snapshot[.systemAudio], .allowed)
    }

    func testScreenCaptureDenialHasRecoveryInstructionsIncludingWrappedErrors() {
        let denial = NSError(domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain", code: -3801)
        let wrapper = NSError(domain: "wrapper", code: 1, userInfo: [NSUnderlyingErrorKey: denial])
        for error in [denial, wrapper] {
            XCTAssertEqual(CaptureErrorPresentation.permission(for: error), .systemAudio)
            XCTAssertTrue(CaptureErrorPresentation.message(for: error).contains("Privacidad y seguridad"))
            XCTAssertTrue(CaptureErrorPresentation.message(for: error).contains("Mantis"))
        }
        let unrelated = NSError(domain: "disk", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disco lleno"])
        XCTAssertNil(CaptureErrorPresentation.permission(for: unrelated))
        XCTAssertEqual(CaptureErrorPresentation.message(for: unrelated), "Disco lleno")
    }

    func testLegacyErrorsAndSettingsLinks() {
        XCTAssertEqual(CaptureErrorPresentation.permission(in: "Screen capture failed: TCC rejection"), .systemAudio)
        for kind in CapturePermissionKind.allCases {
            XCTAssertEqual(kind.settingsURL.scheme, "x-apple.systempreferences")
            XCTAssertTrue(kind.settingsURL.absoluteString.contains(kind == .microphone ? "Privacy_Microphone" : "Privacy_ScreenCapture"))
            XCTAssertTrue(CaptureErrorPresentation.message(for: CaptureAuthorizationError(kind)).contains(kind.settingsSection))
        }
    }
}

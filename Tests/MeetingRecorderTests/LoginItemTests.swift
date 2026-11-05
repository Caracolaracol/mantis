import ServiceManagement
import XCTest
@testable import MeetingRecorder

final class LoginItemTests: XCTestCase {
    @MainActor
    func testLoginRegistrationChangesOnlyOnExplicitAction() {
        var status: SMAppService.Status = .notRegistered
        var calls: [Bool] = []
        let controller = LoginItemController(readStatus: { status }, changeRegistration: { enabled in
            calls.append(enabled)
            status = enabled ? .enabled : .notRegistered
        })
        XCTAssertTrue(calls.isEmpty)
        XCTAssertFalse(controller.isRegistered)
        controller.setEnabled(true)
        XCTAssertTrue(controller.isRegistered)
        controller.setEnabled(false)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertEqual(calls, [true, false])
    }

    @MainActor
    func testPendingApprovalIsRegisteredAndExternalChangesRefresh() {
        var status: SMAppService.Status = .requiresApproval
        let controller = LoginItemController(readStatus: { status }, changeRegistration: { _ in })
        XCTAssertTrue(controller.isRegistered)
        XCTAssertEqual(controller.status, .requiresApproval)
        status = .notRegistered
        controller.refresh()
        XCTAssertFalse(controller.isRegistered)
    }

    @MainActor
    func testFailedRegistrationReportsErrorWithoutPretendingEnabled() {
        let controller = LoginItemController(readStatus: { .notRegistered }, changeRegistration: { _ in
            throw NSError(domain: "SyntheticLoginFailure", code: 1)
        })
        controller.setEnabled(true)
        XCTAssertNotNil(controller.error)
        XCTAssertFalse(controller.isRegistered)
    }
}

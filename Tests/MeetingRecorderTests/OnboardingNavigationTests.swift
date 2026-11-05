import XCTest
@testable import MeetingRecorder

final class OnboardingNavigationTests: XCTestCase {
    @MainActor
    func testNewFolderIsAppliedByPrimaryContinueActionBeforeAdvancing() async throws {
        let navigation = OnboardingNavigation()
        try await navigation.advance(applyLibrary: { XCTFail("Not the folder step") }, finish: {})
        XCTAssertEqual(navigation.step, 1)
        XCTAssertEqual(navigation.primaryTitle(changingLibrary: true), "Usar carpeta y continuar")
        var applied = false
        try await navigation.advance(applyLibrary: {
            XCTAssertEqual(navigation.step, 1)
            XCTAssertTrue(navigation.advancing)
            XCTAssertEqual(navigation.primaryTitle(changingLibrary: true), "Guardando carpeta…")
            applied = true
        }, finish: {})
        XCTAssertTrue(applied)
        XCTAssertEqual(navigation.step, 2)
        XCTAssertFalse(navigation.advancing)
    }

    @MainActor
    func testFolderFailureKeepsStepAndAllowsRetry() async throws {
        struct CopyFailure: Error {}
        let navigation = OnboardingNavigation()
        try await navigation.advance(applyLibrary: {}, finish: {})
        do {
            try await navigation.advance(applyLibrary: { throw CopyFailure() }, finish: {})
            XCTFail("Expected copy failure")
        } catch is CopyFailure {}
        XCTAssertEqual(navigation.step, 1)
        XCTAssertFalse(navigation.advancing)
        try await navigation.advance(applyLibrary: {}, finish: {})
        XCTAssertEqual(navigation.step, 2)
    }

    @MainActor
    func testRepeatedContinueCannotSkipStepWhileCopying() async throws {
        let navigation = OnboardingNavigation()
        try await navigation.advance(applyLibrary: {}, finish: {})
        try await navigation.advance(applyLibrary: {
            navigation.back()
            XCTAssertEqual(navigation.step, 1)
            try await navigation.advance(applyLibrary: { XCTFail("Duplicate copy") }, finish: { XCTFail("Not finishing") })
        }, finish: {})
        XCTAssertEqual(navigation.step, 2)
    }

    @MainActor
    func testExistingLocationNeedsNoSeparateConfirmationAndFinishesNormally() async throws {
        let navigation = OnboardingNavigation()
        try await navigation.advance(applyLibrary: {}, finish: {})
        XCTAssertEqual(navigation.primaryTitle(changingLibrary: false), "Continuar")
        try await navigation.advance(applyLibrary: {}, finish: {})
        try await navigation.advance(applyLibrary: {}, finish: {})
        XCTAssertEqual(navigation.primaryTitle(changingLibrary: false), "Abrir Mantis")
        var completed = false
        try await navigation.advance(applyLibrary: { XCTFail("Not copying") }, finish: { completed = true })
        XCTAssertTrue(completed)
    }
}

import XCTest
import MeetingCore
@testable import MeetingRecorder

final class OnboardingTranscriptionTests: XCTestCase {
    func testExistingModelIsOfferedAndExplicitlyConfirmedWithoutEnablingAutomation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ModelChoiceTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ModelStore(directory: root)
        let source = root.appendingPathComponent("source.gguf")
        try Data("GGUFfixture".utf8).write(to: source)
        try store.importModel(from: source)
        let choice = OnboardingTranscriptionChoice(activeFileName: store.selectedFileName,
            availableFileNames: store.localModels.map(\.id), automaticTranscription: false)
        XCTAssertEqual(choice.modelFileName, "default.gguf")
        XCTAssertEqual(choice.confirmationTitle, "Usar modelo y abrir Mantis")
        XCTAssertFalse(try choice.apply(to: store))
        XCTAssertEqual(store.selectedFileName, "default.gguf")
    }

    func testChooseLaterDisablesAutomaticTranscriptionWithoutDeletingModel() throws {
        var choice = OnboardingTranscriptionChoice(activeFileName: "default.gguf", availableFileNames: ["default.gguf"], automaticTranscription: true)
        choice.modelFileName = nil
        XCTAssertFalse(choice.automaticTranscription)
        XCTAssertFalse(try choice.apply(to: nil))
        XCTAssertEqual(choice.confirmationTitle, "Abrir Mantis (solo audio)")
    }

    func testMissingModelIsNotSilentlyAccepted() {
        let detected = OnboardingTranscriptionChoice(activeFileName: "missing.gguf", availableFileNames: [], automaticTranscription: true)
        XCTAssertNil(detected.modelFileName)
        XCTAssertFalse(detected.automaticTranscription)
        var invalid = detected
        invalid.modelFileName = "missing.gguf"
        XCTAssertThrowsError(try invalid.apply(to: nil))
    }

    @MainActor
    func testModelConfirmationFailureKeepsFinalStepOpen() async throws {
        struct ModelFailure: Error {}
        let navigation = OnboardingNavigation()
        for _ in 0..<3 { try await navigation.advance(applyLibrary: {}, finish: {}) }
        do {
            try await navigation.advance(applyLibrary: {}, finish: { throw ModelFailure() })
            XCTFail("Expected failure")
        } catch is ModelFailure {}
        XCTAssertEqual(navigation.step, 3)
        XCTAssertFalse(navigation.advancing)
    }
}

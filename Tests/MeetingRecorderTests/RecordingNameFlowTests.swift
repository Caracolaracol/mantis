import Combine
import MeetingCore
import ScreenCaptureKit
import XCTest
@testable import MeetingRecorder

@MainActor
private final class SavedRecordingBackend: RecordingBackend {
    let microphoneLevel: Double = 0
    let microphoneIsRecording = true
    let captureFailure: String? = nil
    var starts = 0
    func preparePermissions(for mode: RecordingMode) async throws {}
    func applications() async throws -> [SCRunningApplication] { [] }
    func stop() async throws {}
    func start(mode: RecordingMode, applicationID: Int32?, destination: URL, route: AudioInputRoute?,
               progress: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        starts += 1
        // The default microphone path already writes directly to its final URL.
        try Data("synthetic saved audio".utf8).write(to: destination)
    }
}

@MainActor
final class RecordingNameFlowTests: XCTestCase {
    private func model(ask: Bool = true) throws -> AppModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RecordingNameFlow-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(preview: true, recorder: SavedRecordingBackend(), previewStore: try MeetingStore(root: root))
        model.mode = .microphone
        model.selectedAudioInputUID = ""
        model.automaticTranscription = false
        model.askForRecordingName = ask
        return model
    }

    private func start(_ model: AppModel) async {
        let started = expectation(description: "Synthetic recording started")
        let observation = model.$activeMeetingID.compactMap { $0 }.first().sink { _ in started.fulfill() }
        model.startRecording()
        await fulfillment(of: [started], timeout: 2)
        observation.cancel()
    }

    private func stop(_ model: AppModel, failure: String? = nil) async {
        let stopped = expectation(description: "Audio finalized")
        let observation = model.$preparing.dropFirst().filter { !$0 }.first().sink { _ in stopped.fulfill() }
        model.stopRecording(captureError: failure)
        await fulfillment(of: [stopped], timeout: 2)
        observation.cancel()
    }

    func testAudioSavedBeforePromptAndPrefilledWithActualFileName() async throws {
        let model = try model()
        await start(model)
        await stop(model)
        let request = try XCTUnwrap(model.pendingRecordingName)
        let meeting = try XCTUnwrap(model.meetings.first(where: { $0.id == request.id }))
        XCTAssertEqual(request.fileStem + "." + request.fileExtension, meeting.audioFileName)
        XCTAssertEqual(meeting.status, .recorded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(model.store).finalAudioURL(for: meeting).path))
        XCTAssertTrue(model.busy)
        model.toggleQuickRecording()
        XCTAssertNil(model.activeMeetingID)
        try model.saveRecordingName(request.id, fileStem: "Daily review")
        XCTAssertNil(model.pendingRecordingName)
        XCTAssertFalse(model.busy)
        let renamed = try XCTUnwrap(model.meetings.first(where: { $0.id == request.id }))
        XCTAssertEqual(renamed.audioFileName, "Daily review.m4a")
        let persisted = try XCTUnwrap(try XCTUnwrap(model.store).load().first)
        XCTAssertEqual(persisted.id, renamed.id)
        XCTAssertEqual(persisted.audioFileName, renamed.audioFileName)
        XCTAssertEqual(persisted.title, renamed.title)
    }

    func testDisabledPromptSavesImmediatelyAndStaysIdle() async throws {
        let model = try model(ask: false)
        await start(model)
        await stop(model)
        XCTAssertNil(model.pendingRecordingName)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.recorderStatus.state, .idle)
        let meeting = try XCTUnwrap(model.meetings.first(where: { $0.status == .recorded }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(model.store).finalAudioURL(for: meeting).path))
    }

    func testClosingPromptKeepsNameAndDuplicateDismissIsHarmless() async throws {
        let model = try model()
        await start(model)
        await stop(model)
        let request = try XCTUnwrap(model.pendingRecordingName)
        model.keepRecordingName(request.id)
        model.keepRecordingName(request.id)
        XCTAssertNil(model.pendingRecordingName)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.meetings.first(where: { $0.id == request.id })?.audioFileName,
                       request.fileStem + "." + request.fileExtension)
    }

    func testRenameErrorKeepsPanelRequestAndOriginalAudio() async throws {
        let model = try model()
        await start(model)
        await stop(model)
        let request = try XCTUnwrap(model.pendingRecordingName)
        XCTAssertThrowsError(try model.saveRecordingName(request.id, fileStem: "../bad"))
        XCTAssertEqual(model.pendingRecordingName, request)
        XCTAssertThrowsError(try model.saveRecordingName(UUID(), fileStem: "Other"))
        XCTAssertEqual(model.pendingRecordingName, request)
        let meeting = try XCTUnwrap(model.meetings.first(where: { $0.id == request.id }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(model.store).finalAudioURL(for: meeting).path))
        model.keepRecordingName(request.id)
    }

    func testFailedRecordingDoesNotOpenNamingPrompt() async throws {
        let model = try model()
        await start(model)
        await stop(model, failure: "Synthetic capture failure")
        XCTAssertNil(model.pendingRecordingName)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.alert, "Synthetic capture failure")
    }

    func testAutomaticTranscriptionWaitsForNamingDecision() async throws {
        let model = try model()
        await start(model)
        model.automaticTranscription = true
        await stop(model)
        let request = try XCTUnwrap(model.pendingRecordingName)
        XCTAssertTrue(request.transcribeAfterNaming)
        XCTAssertNil(model.processingID)
        XCTAssertNil(model.alert)
        // No model installed in previews: only after naming should transcription validate it.
        model.keepRecordingName(request.id)
        XCTAssertNil(model.pendingRecordingName)
        XCTAssertNotNil(model.alert)
    }

    func testPreviewNamingPreferenceDoesNotTouchRealDefaults() {
        let defaults = UserDefaults.standard
        let before = defaults.object(forKey: RecordingPreferences.askForRecordingNameKey) as? NSObject
        let model = AppModel(preview: true)
        model.askForRecordingName.toggle()
        XCTAssertEqual(defaults.object(forKey: RecordingPreferences.askForRecordingNameKey) as? NSObject, before)
    }
}

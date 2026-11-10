import Combine
import MeetingCore
import ScreenCaptureKit
import XCTest
@testable import MeetingRecorder

@MainActor
private final class PendingRecordingBackend: RecordingBackend {
    let microphoneLevel: Double = 0
    let microphoneIsRecording = false
    let captureFailure: String? = nil
    var timeout: TimeInterval?
    var began: (() -> Void)?
    var completion: ((Result<Void, Error>) -> Void)?
    var calls = 0
    var completedStarts = 0
    var aborts = 0

    func preparePermissions(for mode: RecordingMode) async throws {}
    func applications() async throws -> [SCRunningApplication] { [] }
    func stop() async throws {}

    func start(mode: RecordingMode, applicationID: Int32?, destination: URL, route: AudioInputRoute?,
               progress: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        calls += 1
        progress("Buscando fuentes de audio…")
        try await CaptureRequest<Void>.perform(timeout: timeout, abort: { self.aborts += 1 }) {
            completion = $0
            began?()
        }
        completedStarts += 1
    }
}

@MainActor
final class RecordingPreparationTests: XCTestCase {
    private func model(_ backend: PendingRecordingBackend) throws -> AppModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RecordingPreparationTests-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(preview: true, recorder: backend, previewStore: try MeetingStore(root: root))
        model.mode = .systemAndMicrophone
        model.selectedAudioInputUID = ""
        model.automaticTranscription = false
        return model
    }

    func testCancelClearsPreparingAndLateCallbackCannotStartRecording() async throws {
        let backend = PendingRecordingBackend()
        let model = try model(backend)
        let began = expectation(description: "Startup began")
        backend.began = { began.fulfill() }
        model.startRecording()
        await fulfillment(of: [began], timeout: 1)
        XCTAssertTrue(model.preparing)
        XCTAssertTrue(model.startingRecording)
        XCTAssertEqual(model.phase, "Buscando fuentes de audio…")
        let finished = expectation(description: "Preparation canceled")
        let observation = model.$startingRecording.dropFirst().filter { !$0 }.sink { _ in finished.fulfill() }
        model.startRecording() // Duplicate clicks must not start another session.
        model.cancelRecordingPreparation()
        await fulfillment(of: [finished], timeout: 1)
        observation.cancel()
        XCTAssertFalse(model.busy)
        XCTAssertFalse(model.preparing)
        XCTAssertEqual(model.phase, "")
        XCTAssertNil(model.activeMeetingID)
        XCTAssertNil(model.alert)
        XCTAssertEqual(backend.calls, 1)
        XCTAssertEqual(backend.aborts, 1)
        backend.completion?(.success(()))
        await Task.yield()
        XCTAssertEqual(backend.completedStarts, 0)
        XCTAssertNil(model.activeMeetingID)
        let saved = try XCTUnwrap(model.store).load()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.status, .failed)
    }

    func testMissingStartupCallbackClearsBusyAndShowsTimeout() async throws {
        let backend = PendingRecordingBackend()
        backend.timeout = 0.02
        let model = try model(backend)
        let finished = expectation(description: "Preparation timed out")
        let observation = model.$startingRecording.dropFirst().filter { !$0 }.sink { _ in finished.fulfill() }
        model.startRecording()
        await fulfillment(of: [finished], timeout: 1)
        observation.cancel()
        XCTAssertFalse(model.preparing)
        XCTAssertFalse(model.busy)
        XCTAssertFalse(model.startingRecording)
        XCTAssertNil(model.activeMeetingID)
        XCTAssertNotNil(model.alert)
        XCTAssertEqual(backend.aborts, 1)
    }

    func testSelectingBothChannelsAndReapplyingSameDevicePreservesSelection() {
        let model = AppModel(preview: true)
        model.selectedAudioInputUID = "synthetic-stereo"
        model.selectedInputChannels = [0]
        model.setInputChannel(1, enabled: true)
        XCTAssertEqual(model.inputRoute?.channels, [0, 1])
        model.selectedAudioInputUID = "synthetic-stereo"
        XCTAssertEqual(model.inputRoute?.channels, [0, 1])
        model.setInputChannel(0, enabled: false)
        XCTAssertEqual(model.inputRoute?.channels, [1])
        model.setInputChannel(1, enabled: false)
        XCTAssertEqual(model.inputRoute?.channels, [1])
    }

    func testPreviewSelectionChangesDoNotPersistRealPreferences() {
        let defaults = UserDefaults.standard
        let keys = ["audioInputUID", "audioInputChannels", "recordingMode", RecordingPreferences.automaticTranscriptionKey]
        let before = keys.map { defaults.object(forKey: $0) as? NSObject }
        let model = AppModel(preview: true)
        model.selectedAudioInputUID = "synthetic-only"
        model.selectedInputChannels = [0, 1]
        model.mode = .systemAudio
        model.automaticTranscription = false
        XCTAssertEqual(keys.map { defaults.object(forKey: $0) as? NSObject }, before)
    }
}

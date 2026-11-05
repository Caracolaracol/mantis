import XCTest
@testable import MeetingCore

final class MeetingCoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingRecorderTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testCaptureModesHaveExplicitSourcesAndLabels() {
        XCTAssertEqual(RecordingMode.microphone.title, "Solo entrada de audio")
        XCTAssertEqual(RecordingMode.systemAndMicrophone.title, "Todo: computador + entrada")
        XCTAssertTrue(RecordingMode.microphone.capturesMicrophone)
        XCTAssertFalse(RecordingMode.microphone.capturesApplication)
        XCTAssertFalse(RecordingMode.applicationOnly.capturesMicrophone)
        XCTAssertTrue(RecordingMode.applicationOnly.capturesApplication)
        XCTAssertTrue(RecordingMode.application.capturesMicrophone)
        XCTAssertTrue(RecordingMode.application.capturesApplication)
    }

    func testWholeComputerModesHaveNoApplicationFilter() {
        XCTAssertTrue(RecordingMode.systemAndMicrophone.capturesWholeSystemAudio)
        XCTAssertTrue(RecordingMode.systemAndMicrophone.capturesMicrophone)
        XCTAssertFalse(RecordingMode.systemAndMicrophone.capturesApplication)
        XCTAssertTrue(RecordingMode.systemAudio.capturesWholeSystemAudio)
        XCTAssertTrue(RecordingMode.systemAudio.capturesScreenAudio)
        XCTAssertFalse(RecordingMode.systemAudio.capturesMicrophone)
        XCTAssertFalse(RecordingMode.systemAudio.capturesApplication)
        XCTAssertFalse(RecordingMode.microphone.capturesScreenAudio)
    }

    func testSavedCaptureModesRemainCompatible() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(RecordingMode.self, from: Data(#""microphone""#.utf8)), .microphone)
        let oldApplication = try decoder.decode(RecordingMode.self, from: Data(#""application""#.utf8))
        XCTAssertEqual(oldApplication, .application)
        XCTAssertTrue(oldApplication.capturesMicrophone)
        for mode in RecordingMode.allCases {
            XCTAssertEqual(try decoder.decode(RecordingMode.self, from: JSONEncoder().encode(mode)), mode)
        }
    }

    func testAllModesRoundTripAndDelete() throws {
        let store = try MeetingStore(root: temporaryDirectory())
        for mode in RecordingMode.allCases {
            var meeting = Meeting(title: "Planificación", mode: mode, audioFileName: "meeting.mov", sourceApplication: "Meet")
            meeting.status = .completed
            meeting.transcript = "Hola, equipo."
            try store.save(meeting)
            let loaded = try XCTUnwrap(store.load().first)
            XCTAssertEqual(loaded.id, meeting.id)
            XCTAssertEqual(loaded.transcript, meeting.transcript)
            XCTAssertEqual(loaded.mode, mode)
            XCTAssertEqual(loaded.status, .completed)
            try store.delete(meeting)
            XCTAssertTrue(try store.load().isEmpty)
        }
    }

    func testRecoverInterruptedOperationsWithoutLosingText() throws {
        let store = try MeetingStore(root: temporaryDirectory())
        for status in [MeetingStatus.recording, .transcribing] {
            var meeting = Meeting(title: "Interrumpida", mode: .application, audioFileName: "meeting.mov", status: status)
            meeting.transcript = "Texto anterior"
            try store.save(meeting)
        }
        let meetings = try store.load()
        XCTAssertEqual(meetings.count, 2)
        XCTAssertTrue(meetings.allSatisfy { $0.status == .interrupted && $0.error != nil && $0.transcript == "Texto anterior" })
    }

    func testRejectAudioPathTraversal() throws {
        let store = try MeetingStore(root: temporaryDirectory())
        for name in ["../secret.wav", "/tmp/a.wav", "..", "", "nested/audio.wav", "x\\y", "x\0y"] {
            let meeting = Meeting(title: "Test", mode: .microphone, audioFileName: name)
            XCTAssertThrowsError(try store.audioURL(for: meeting))
            XCTAssertThrowsError(try store.save(meeting))
        }
    }

    func testReportCorruptManifestWithoutDeletingIt() throws {
        let store = try MeetingStore(root: temporaryDirectory())
        let meeting = Meeting(title: "Test", mode: .microphone, audioFileName: "a.caf")
        try store.save(meeting)
        let manifest = store.directory(for: meeting.id).appendingPathComponent("meeting.json")
        try Data("broken".utf8).write(to: manifest)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try String(contentsOf: manifest, encoding: .utf8), "broken")
    }

    func testModelsAreCopiedAndReplacedInOwnLibrary() throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.gguf")
        let store = try ModelStore(directory: directory.appendingPathComponent("Models"))
        XCTAssertFalse(store.isReady)
        try Data("GGUFfirst".utf8).write(to: source)
        try store.importModel(from: source)
        XCTAssertTrue(store.isReady)
        try Data("GGUFsecond".utf8).write(to: source)
        try store.importModel(from: source)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try String(contentsOf: store.modelURL, encoding: .utf8), "GGUFsecond")
    }

    func testRejectNonGGUFWithoutReplacingExistingModel() throws {
        let directory = try temporaryDirectory()
        let store = try ModelStore(directory: directory.appendingPathComponent("Models"))
        let source = directory.appendingPathComponent("source.gguf")
        try Data("GGUFvalid".utf8).write(to: source)
        try store.importModel(from: source)
        try Data("not a model".utf8).write(to: source)
        XCTAssertThrowsError(try store.importModel(from: source))
        XCTAssertEqual(try String(contentsOf: store.modelURL, encoding: .utf8), "GGUFvalid")
    }

    func testCancellationIsSafeAndPreventsModelLoading() async throws {
        let token = TranscriptionCancellation()
        XCTAssertFalse(token.isCancelled)
        token.cancel()
        XCTAssertTrue(token.isCancelled)
        do {
            _ = try await NativeTranscriber().transcribe(wav: URL(fileURLWithPath: "/missing.wav"),
                                                         modelURL: URL(fileURLWithPath: "/missing.gguf"), cancellation: token)
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
    }

    func testAutomaticTranscriptionIsOffByDefaultAndPersistsOptIn() throws {
        let suite = "MeetingRecorderTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(RecordingPreferences.automaticTranscription(defaults: defaults))
        RecordingPreferences.setAutomaticTranscription(true, defaults: defaults)
        XCTAssertTrue(RecordingPreferences.automaticTranscription(defaults: defaults))
        RecordingPreferences.setAutomaticTranscription(false, defaults: defaults)
        XCTAssertFalse(RecordingPreferences.automaticTranscription(defaults: defaults))
    }

    func testControlQueueIsOrderedAndExpiresOldCommands() throws {
        let control = try RecorderControl(directory: temporaryDirectory())
        try control.send(.stop, now: 1)
        try control.send(.show, now: 100)
        try control.send(.toggle, now: 101)
        try control.send(.cancel, now: 200)
        XCTAssertEqual(try control.drain(now: 102), [.show, .toggle])
        XCTAssertTrue(try control.drain(now: 102).isEmpty)
    }

    func testControlPublishesMachineReadableStatus() throws {
        let control = try RecorderControl(directory: temporaryDirectory())
        let status = RecorderStatus(state: .recording, elapsedSeconds: 42)
        try control.publish(status)
        let loaded = try JSONDecoder().decode(RecorderStatus.self, from: Data(contentsOf: control.statusURL))
        XCTAssertEqual(loaded, status)
        XCTAssertEqual(loaded.pid, ProcessInfo.processInfo.processIdentifier)
    }

    func testOnlyOneInstanceOwnsRecorderLock() throws {
        let directory = try temporaryDirectory()
        var first: RecorderInstanceLock? = try RecorderInstanceLock(directory: directory)
        XCTAssertTrue(try XCTUnwrap(first).isOwner)
        let second = try RecorderInstanceLock(directory: directory)
        XCTAssertFalse(second.isOwner)
        first = nil
        let third = try RecorderInstanceLock(directory: directory)
        XCTAssertTrue(third.isOwner)
        withExtendedLifetime(second) {}
    }

    func testNativeEngineIsLinked() {
        XCTAssertTrue(NativeTranscriber.version.hasPrefix("0.4."))
    }

    func testChunkBoundaryPrefersSilenceAndDoesNotDuplicateFrames() {
        var samples = [Float](repeating: 1, count: 64_000)
        for index in 59_200..<60_800 { samples[index] = 0 }
        let boundary = samples.withUnsafeBufferPointer {
            NativeTranscriber.chunkBoundary(samples: $0.baseAddress!, count: $0.count, hasMore: true)
        }
        XCTAssertEqual(boundary, 60_800)
        let final = samples.withUnsafeBufferPointer {
            NativeTranscriber.chunkBoundary(samples: $0.baseAddress!, count: $0.count, hasMore: false)
        }
        XCTAssertEqual(final, 64_000)
    }
}

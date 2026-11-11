import MeetingCore
import XCTest

final class RecordingNameTests: XCTestCase {
    private func store() throws -> MeetingStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RecordingNameTests-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try MeetingStore(root: root, textRoot: root.appendingPathComponent("texts"))
    }

    private func recording(in store: MeetingStore) throws -> Meeting {
        let meeting = try store.create(Meeting(mode: .microphone, audioFileName: "audio.m4a",
                                              createdAt: Date(timeIntervalSince1970: 1_799_000_000)))
        try Data("saved audio".utf8).write(to: store.finalAudioURL(for: meeting))
        return meeting
    }

    func testNamingPreferenceDefaultsOnAndCanBeDisabledPersistently() throws {
        let name = "RecordingNamePreference-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(RecordingPreferences.askForRecordingName(defaults: defaults))
        RecordingPreferences.setAskForRecordingName(false, defaults: defaults)
        XCTAssertFalse(RecordingPreferences.askForRecordingName(defaults: defaults))
        RecordingPreferences.setAskForRecordingName(true, defaults: defaults)
        XCTAssertTrue(RecordingPreferences.askForRecordingName(defaults: defaults))
    }

    func testRenameMovesActualAudioAndTXTAndUpdatesManifest() throws {
        let store = try store()
        let original = try recording(in: store)
        try "transcript".write(to: store.transcriptURL(for: original), atomically: true, encoding: .utf8)
        let renamed = try store.renamingRecording(original, toFileStem: "  Entrevista  ")
        XCTAssertEqual(renamed.audioFileName, "Entrevista.m4a")
        XCTAssertEqual(renamed.title, "Entrevista")
        XCTAssertEqual(try Data(contentsOf: store.finalAudioURL(for: renamed)), Data("saved audio".utf8))
        XCTAssertEqual(try String(contentsOf: store.transcriptURL(for: renamed), encoding: .utf8), "transcript")
        XCTAssertFalse(FileManager.default.fileExists(atPath: try store.finalAudioURL(for: original).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try store.transcriptURL(for: original).path))
        XCTAssertEqual(try store.load().first, renamed)
    }

    func testUnchangedNameAndTypedExtensionDoNotDuplicateSuffix() throws {
        let store = try store()
        let original = try recording(in: store)
        let same = try store.renamingRecording(original, toFileStem: original.audioFileName)
        XCTAssertEqual(same.audioFileName, original.audioFileName)
        let renamed = try store.renamingRecording(same, toFileStem: "Notes.M4A")
        XCTAssertEqual(renamed.audioFileName, "Notes.m4a")
    }

    func testConflictingAudioOrTXTNeverOverwritesAnything() throws {
        let store = try store()
        let original = try recording(in: store)
        for file in [store.root.appendingPathComponent("Occupied.m4a"), store.textRoot.appendingPathComponent("TextOnly.txt")] {
            try Data("existing".utf8).write(to: file)
        }
        for name in ["Occupied", "TextOnly"] {
            XCTAssertThrowsError(try store.renamingRecording(original, toFileStem: name))
            XCTAssertEqual(try Data(contentsOf: store.finalAudioURL(for: original)), Data("saved audio".utf8))
        }
        XCTAssertEqual(try Data(contentsOf: store.root.appendingPathComponent("Occupied.m4a")), Data("existing".utf8))
        XCTAssertEqual(try Data(contentsOf: store.textRoot.appendingPathComponent("TextOnly.txt")), Data("existing".utf8))
    }

    func testInvalidAndOversizedNamesLeaveOriginalIntact() throws {
        let store = try store()
        let original = try recording(in: store)
        for name in ["", "  ", ".", "..", "../outside", "nested/name", "back\\slash", "hidden\0name", ".hidden", "colon:name", "line\nbreak", String(repeating: "é", count: 130)] {
            XCTAssertThrowsError(try store.renamingRecording(original, toFileStem: name), name)
        }
        XCTAssertEqual(try store.load().first, original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try store.finalAudioURL(for: original).path))
    }

    func testReservedNameWithoutAudioStillCannotBeReused() throws {
        let store = try store()
        let original = try recording(in: store)
        var reserved = try store.create(Meeting(mode: .microphone, audioFileName: "audio.m4a"))
        reserved.audioFileName = "Reserved.m4a"
        try store.save(reserved)
        XCTAssertThrowsError(try store.renamingRecording(original, toFileStem: "reserved"))
    }

    func testManifestFailureRollsBackAudioMove() throws {
        let store = try store()
        // Legacy layout avoids the flat-library preflight so failure occurs after moving audio.
        let original = Meeting(mode: .microphone, audioFileName: "audio.m4a")
        try store.save(original)
        try Data("audio".utf8).write(to: store.finalAudioURL(for: original))
        let manifest = try store.directory(for: original).appendingPathComponent("meeting.json")
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.renamingRecording(original, toFileStem: "Changed"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try store.finalAudioURL(for: original).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try store.directory(for: original).appendingPathComponent("Changed.m4a").path))
    }
}

import XCTest
import MeetingCore

final class FlatStorageTests: XCTestCase {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FlatStorageTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testRecoveryCaptureRemainsAccessibleWithoutMislabelingItAsM4A() throws {
        let root = try root()
        let store = try MeetingStore(root: root.appendingPathComponent("Source"))
        let meeting = try store.create(Meeting(mode: .systemAudio, audioFileName: "audio.m4a"))
        let capture = try store.captureURL(for: meeting)
        try Data("original capture".utf8).write(to: capture)
        XCTAssertEqual(try store.audioURL(for: meeting), capture)
        XCTAssertTrue(try store.transcriptURL(for: meeting).lastPathComponent.hasPrefix("Reunión "))
        let copy = try store.copyingLibrary(to: root.appendingPathComponent("Copy"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try copy.finalAudioURL(for: meeting).path))
        XCTAssertEqual(try Data(contentsOf: copy.audioURL(for: meeting)), Data("original capture".utf8))
    }

    func testAudioAndTextShareOneFolderWithReadableFileNames() throws {
        let store = try MeetingStore(root: root())
        let meeting = try store.create(Meeting(mode: .systemAudio, audioFileName: "meeting.mov"))
        let audio = try store.audioURL(for: meeting)
        let text = try store.transcriptURL(for: meeting)
        XCTAssertEqual(audio.deletingLastPathComponent().path, store.root.path)
        XCTAssertEqual(text.deletingLastPathComponent().path, store.root.path)
        XCTAssertTrue(audio.lastPathComponent.hasPrefix("Reunión "))
        XCTAssertEqual(audio.deletingPathExtension().lastPathComponent, text.deletingPathExtension().lastPathComponent)
        try Data("audio".utf8).write(to: audio)
        try Data("texto".utf8).write(to: text)
        let visible = try FileManager.default.contentsOfDirectory(atPath: store.root.path).filter { !$0.hasPrefix(".") }
        XCTAssertEqual(Set(visible), [audio.lastPathComponent, text.lastPathComponent])
        XCTAssertEqual(try store.load().first?.id, meeting.id)
    }

    func testSameMinuteAndExistingUserFilesAreNeverOverwritten() throws {
        let store = try MeetingStore(root: root())
        let date = Date(timeIntervalSince1970: 1_794_000_000)
        let userFile = store.root.appendingPathComponent(Meeting.automaticFileStem(for: date) + ".txt")
        try Data("user work".utf8).write(to: userFile)
        let first = try store.create(Meeting(mode: .microphone, audioFileName: "microphone.m4a", createdAt: date))
        let second = try store.create(Meeting(mode: .systemAudio, audioFileName: "meeting.mov", createdAt: date))
        XCTAssertTrue(first.audioFileName.contains("(2)"))
        XCTAssertTrue(second.audioFileName.contains("(3)"))
        XCTAssertEqual(try Data(contentsOf: userFile), Data("user work".utf8))
        XCTAssertThrowsError(try store.create(first))
    }

    func testLegacyFoldersRemainReadableWithoutMovingOriginals() throws {
        let store = try MeetingStore(root: root())
        let old = Meeting(mode: .microphone, audioFileName: "microphone.m4a")
        try store.save(old)
        let original = try store.audioURL(for: old)
        try Data("legacy".utf8).write(to: original)
        _ = try store.create(Meeting(mode: .microphone, audioFileName: "microphone.m4a"))
        XCTAssertEqual(try store.load().count, 2)
        XCTAssertEqual(try store.audioURL(for: old), original)
        XCTAssertEqual(try Data(contentsOf: original), Data("legacy".utf8))
    }

    func testOptionalTextFolderCopiesTextsAndLeavesAudioUntouched() throws {
        let root = try root()
        let store = try MeetingStore(root: root.appendingPathComponent("Mantis"))
        let meeting = try store.create(Meeting(mode: .microphone, audioFileName: "microphone.m4a"))
        let audio = try store.audioURL(for: meeting)
        let text = try store.transcriptURL(for: meeting)
        try Data("audio".utf8).write(to: audio)
        try Data("texto".utf8).write(to: text)
        let split = try store.copyingTranscripts(to: root.appendingPathComponent("Textos"))
        XCTAssertEqual(try split.audioURL(for: meeting), audio)
        XCTAssertEqual(try Data(contentsOf: split.transcriptURL(for: meeting)), Data("texto".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: text.path))
        let together = try split.copyingTranscripts(to: store.root)
        XCTAssertEqual(together.root.path, together.textRoot.path)
        XCTAssertEqual(try together.transcriptURL(for: meeting), text)
    }

    func testChangingAudioFolderPreservesTextLocation() throws {
        let root = try root()
        let store = try MeetingStore(root: root.appendingPathComponent("Original"))
        let meeting = try store.create(Meeting(mode: .microphone, audioFileName: "audio.m4a"))
        let audio = try store.audioURL(for: meeting)
        let text = try store.transcriptURL(for: meeting)
        try Data("audio".utf8).write(to: audio)
        try Data("texto".utf8).write(to: text)

        let updated = try store.copyingLibrary(to: root.appendingPathComponent("Audios"), keepingTextFolder: true)
        XCTAssertEqual(updated.textRoot, store.textRoot)
        XCTAssertEqual(try updated.transcriptURL(for: meeting), text)
        XCTAssertEqual(try Data(contentsOf: updated.audioURL(for: meeting)), Data("audio".utf8))
        XCTAssertEqual(try Data(contentsOf: updated.transcriptURL(for: meeting)), Data("texto".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: updated.root.appendingPathComponent(text.lastPathComponent).path))

        let split = try updated.copyingTranscripts(to: root.appendingPathComponent("Textos"))
        let copied = try split.copyingLibrary(to: root.appendingPathComponent("OtrosAudios"), keepingTextFolder: true)
        XCTAssertEqual(copied.textRoot, split.textRoot)
        XCTAssertEqual(try copied.transcriptURL(for: meeting), try split.transcriptURL(for: meeting))
        XCTAssertEqual(try Data(contentsOf: copied.audioURL(for: meeting)), Data("audio".utf8))
    }

    func testExplicitConsolidationFlattensLegacyAudioAndPreservesOriginalBackup() throws {
        let store = try MeetingStore(root: root())
        let old = Meeting(mode: .microphone, audioFileName: "microphone.m4a")
        try store.save(old)
        try Data("legacy audio".utf8).write(to: store.audioURL(for: old))
        try Data("legacy text".utf8).write(to: store.transcriptURL(for: old))
        _ = try store.consolidatingLegacyRecordings()
        let updated = try XCTUnwrap(store.load().first)
        XCTAssertEqual(updated.id, old.id)
        XCTAssertEqual(updated.storageLayout, .flat)
        XCTAssertEqual(try store.audioURL(for: updated).deletingLastPathComponent().path, store.root.path)
        XCTAssertEqual(try store.transcriptURL(for: updated).deletingLastPathComponent().path, store.root.path)
        XCTAssertEqual(try Data(contentsOf: store.audioURL(for: updated)), Data("legacy audio".utf8))
        XCTAssertEqual(try Data(contentsOf: store.transcriptURL(for: updated)), Data("legacy text".utf8))
        let backup = store.root.appendingPathComponent(".mantis/PreviousFolders/\(old.id.uuidString)/microphone.m4a")
        XCTAssertEqual(try Data(contentsOf: backup), Data("legacy audio".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(for: old.id).path))
        _ = try store.consolidatingLegacyRecordings()
        XCTAssertEqual(try store.load().count, 1)
    }

    func testConsolidationConflictLeavesLegacyOriginalInPlace() throws {
        let store = try MeetingStore(root: root())
        let old = Meeting(mode: .microphone, audioFileName: "microphone.m4a")
        try store.save(old)
        let audio = try store.audioURL(for: old)
        try Data("original".utf8).write(to: audio)
        let backup = store.root.appendingPathComponent(".mantis/PreviousFolders/\(old.id.uuidString)")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.consolidatingLegacyRecordings())
        XCTAssertEqual(try Data(contentsOf: audio), Data("original".utf8))
        XCTAssertEqual(try store.load().first?.storageLayout, nil)
    }

    func testTextFolderConflictDoesNotOverwriteUserFile() throws {
        let root = try root()
        let store = try MeetingStore(root: root.appendingPathComponent("Audio"))
        let meeting = try store.create(Meeting(mode: .microphone, audioFileName: "audio.m4a"))
        try Data("transcript".utf8).write(to: store.transcriptURL(for: meeting))
        let target = root.appendingPathComponent("Text")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let conflict = target.appendingPathComponent(try store.transcriptURL(for: meeting).lastPathComponent)
        try Data("user work".utf8).write(to: conflict)
        XCTAssertThrowsError(try store.copyingTranscripts(to: target))
        XCTAssertEqual(try Data(contentsOf: conflict), Data("user work".utf8))
        XCTAssertEqual(try Data(contentsOf: store.transcriptURL(for: meeting)), Data("transcript".utf8))
    }

    func testFlatLibraryCopyAndDeletionPreserveUnrelatedFiles() throws {
        let root = try root()
        let source = try MeetingStore(root: root.appendingPathComponent("Source"))
        let meeting = try source.create(Meeting(mode: .microphone, audioFileName: "microphone.m4a"))
        try Data("audio".utf8).write(to: source.audioURL(for: meeting))
        try Data("texto".utf8).write(to: source.transcriptURL(for: meeting))
        let copy = try source.copyingLibrary(to: root.appendingPathComponent("Copy"))
        XCTAssertEqual(try copy.load().first?.id, meeting.id)
        XCTAssertEqual(try Data(contentsOf: copy.audioURL(for: meeting)), Data("audio".utf8))
        XCTAssertEqual(try Data(contentsOf: copy.transcriptURL(for: meeting)), Data("texto".utf8))
        let unrelated = copy.root.appendingPathComponent("notes.txt")
        try Data("user".utf8).write(to: unrelated)
        try copy.delete(meeting)
        XCTAssertTrue(try copy.load().isEmpty)
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("user".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try source.audioURL(for: meeting).path))
    }
}

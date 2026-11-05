import XCTest
import MeetingCore

final class LibraryPreferencesTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testSimpleDefaultLegacyPreservationAndExplicitSelection() throws {
        let root = try root()
        let suite = "MantisLibraryTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let home = root.appendingPathComponent("Home")
        let support = root.appendingPathComponent("Support")
        let suggested = home.appendingPathComponent("Mantis")
        XCTAssertEqual(LibraryPreferences.initialRoot(defaults: defaults, home: home, applicationSupport: support).path, suggested.path)
        let legacy = support.appendingPathComponent("MeetingRecorder/Meetings")
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent(UUID().uuidString), withIntermediateDirectories: true)
        XCTAssertEqual(LibraryPreferences.initialRoot(defaults: defaults, home: home, applicationSupport: support).path, legacy.path)
        let chosen = root.appendingPathComponent("Chosen")
        LibraryPreferences.setRoot(chosen, defaults: defaults)
        XCTAssertEqual(LibraryPreferences.initialRoot(defaults: defaults, home: home, applicationSupport: support).path, chosen.path)
        XCTAssertFalse(LibraryPreferences.setupCompleted(defaults: defaults))
        XCTAssertNil(LibraryPreferences.transcriptRoot(defaults: defaults))
        LibraryPreferences.setTranscriptRoot(chosen, defaults: defaults)
        XCTAssertEqual(LibraryPreferences.transcriptRoot(defaults: defaults)?.path, chosen.path)
        LibraryPreferences.setTranscriptRoot(nil, defaults: defaults)
        XCTAssertNil(LibraryPreferences.transcriptRoot(defaults: defaults))
        LibraryPreferences.completeSetup(defaults: defaults)
        XCTAssertTrue(LibraryPreferences.setupCompleted(defaults: defaults))
    }

    func testSetupCompletionPersistsAcrossLaunchesWithoutChangingFolder() throws {
        let suite = "MantisSetupLaunchTests-\(UUID())"
        let firstLaunch = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { firstLaunch.removePersistentDomain(forName: suite) }
        XCTAssertFalse(LibraryPreferences.setupCompleted(defaults: firstLaunch))
        let folder = URL(fileURLWithPath: "/Users/test/Mantis", isDirectory: true)
        LibraryPreferences.setRoot(folder, defaults: firstLaunch)
        // Choosing a folder alone does not mark the other setup steps completed.
        XCTAssertFalse(LibraryPreferences.setupCompleted(defaults: firstLaunch))
        LibraryPreferences.completeSetup(defaults: firstLaunch)
        let nextLaunch = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertTrue(LibraryPreferences.setupCompleted(defaults: nextLaunch))
        XCTAssertEqual(LibraryPreferences.initialRoot(defaults: nextLaunch).path, folder.path)
    }

    func testLibraryCopyKeepsAudioTextAndOriginals() throws {
        let root = try root()
        let source = try MeetingStore(root: root.appendingPathComponent("Old"))
        var meeting = Meeting(mode: .microphone, audioFileName: "microphone.m4a")
        meeting.transcript = "Texto de prueba"
        meeting.status = .completed
        try source.save(meeting)
        let audio = Data("synthetic audio".utf8)
        try audio.write(to: source.audioURL(for: meeting))
        let text = source.directory(for: meeting.id).appendingPathComponent("transcript.txt")
        try "Texto de prueba".write(to: text, atomically: true, encoding: .utf8)
        let copied = try source.copyingLibrary(to: root.appendingPathComponent("Mantis"))
        XCTAssertEqual(try copied.load().first?.id, meeting.id)
        XCTAssertEqual(try copied.load().first?.transcript, meeting.transcript)
        XCTAssertEqual(try Data(contentsOf: copied.audioURL(for: meeting)), audio)
        XCTAssertEqual(try Data(contentsOf: copied.directory(for: meeting.id).appendingPathComponent("transcript.txt")), try Data(contentsOf: text))
        XCTAssertEqual(try Data(contentsOf: source.audioURL(for: meeting)), audio)
        XCTAssertEqual(try source.load().count, 1)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: copied.root.path).contains(where: { $0.hasPrefix(".mantis-copy-") }))
    }

    func testCopyRejectsCollisionsAndNestedDirectoriesWithoutOverwriting() throws {
        let root = try root()
        let source = try MeetingStore(root: root.appendingPathComponent("Source"))
        let target = try MeetingStore(root: root.appendingPathComponent("Target"))
        let meeting = Meeting(title: "Original", mode: .microphone, audioFileName: "audio.m4a")
        try source.save(meeting)
        var conflicting = meeting
        conflicting.title = "Do not overwrite"
        try target.save(conflicting)
        XCTAssertThrowsError(try source.copyingLibrary(to: target.root))
        XCTAssertEqual(try target.load().first?.title, conflicting.title)
        XCTAssertEqual(try source.load().first?.title, meeting.title)
        XCTAssertThrowsError(try source.copyingLibrary(to: source.root.appendingPathComponent("Nested")))
        XCTAssertThrowsError(try source.copyingLibrary(to: root))
        XCTAssertEqual(try source.copyingLibrary(to: source.root).root, source.root)
    }

    func testCopyPreservesUnrelatedDestinationFiles() throws {
        let root = try root()
        let source = try MeetingStore(root: root.appendingPathComponent("Source"))
        let target = try MeetingStore(root: root.appendingPathComponent("Target"))
        let unrelated = target.root.appendingPathComponent("notes.txt")
        try Data("user work".utf8).write(to: unrelated)
        try source.save(Meeting(mode: .microphone, audioFileName: "audio.m4a"))
        _ = try source.copyingLibrary(to: target.root)
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("user work".utf8))
    }
}

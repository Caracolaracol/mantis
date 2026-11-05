import XCTest
import MeetingCore

final class MeetingTitleTests: XCTestCase {
    func testAutomaticTitleUsesCreationDateAndTimeZone() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-04T22:15:00Z"))
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: -3 * 3600))
        XCTAssertEqual(Meeting.automaticTitle(for: date, timeZone: zone), "Reunión 04-11-2026 19:15")
        let meeting = Meeting(mode: .systemAndMicrophone, audioFileName: "meeting.mov", createdAt: date)
        XCTAssertEqual(meeting.createdAt, date)
        XCTAssertEqual(meeting.title, Meeting.automaticTitle(for: meeting.createdAt))
        XCTAssertEqual(Meeting(mode: .microphone, audioFileName: "imported.wav", createdAt: date).title, meeting.title)
    }

    func testRenamePersistsWithoutChangingAudioOrMeetingIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingTitleTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MeetingStore(root: root)
        var meeting = Meeting(mode: .microphone, audioFileName: "microphone.m4a")
        try store.save(meeting)
        let original = meeting
        let audio = try store.audioURL(for: meeting)
        try Data("original audio".utf8).write(to: audio)
        try meeting.rename(to: "  Planificación del equipo\n")
        try store.save(meeting)
        let loaded = try XCTUnwrap(store.load().first)
        XCTAssertEqual(loaded.title, "Planificación del equipo")
        XCTAssertEqual(loaded.id, original.id)
        XCTAssertEqual(loaded.createdAt.timeIntervalSince1970, original.createdAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(try store.audioURL(for: loaded), audio)
        XCTAssertEqual(try Data(contentsOf: audio), Data("original audio".utf8))
        XCTAssertThrowsError(try meeting.rename(to: " \n\t"))
        XCTAssertEqual(meeting.title, "Planificación del equipo")
    }
}

import Foundation
import MeetingCore

struct RecordingNameRequest: Identifiable, Equatable {
    let id: UUID
    let fileStem: String
    let fileExtension: String
    let transcribeAfterNaming: Bool

    init(meeting: Meeting, transcribeAfterNaming: Bool) {
        id = meeting.id
        let file = URL(fileURLWithPath: meeting.audioFileName)
        fileStem = file.deletingPathExtension().lastPathComponent
        fileExtension = file.pathExtension
        self.transcribeAfterNaming = transcribeAfterNaming
    }
}

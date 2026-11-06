import Foundation

public enum RecordingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    // Preserve the original raw value: saved "application" meetings include the mic.
    case systemAndMicrophone, systemAudio, microphone, applicationOnly, application
    public var id: String { rawValue }
    public var capturesMicrophone: Bool { self == .microphone || self == .application || self == .systemAndMicrophone }
    public var capturesApplication: Bool { self == .application || self == .applicationOnly }
    public var capturesWholeSystemAudio: Bool { self == .systemAudio || self == .systemAndMicrophone }
    public var capturesScreenAudio: Bool { capturesApplication || capturesWholeSystemAudio }

    public var title: String {
        switch self {
        case .systemAndMicrophone: return AppLocalization.text("Todo: computador + entrada")
        case .systemAudio: return AppLocalization.text("Solo audio del computador")
        case .microphone: return AppLocalization.text("Solo entrada de audio")
        case .applicationOnly: return AppLocalization.text("Solo audio de la aplicación")
        case .application: return AppLocalization.text("Aplicación + entrada de audio")
        }
    }

    public var explanation: String {
        switch self {
        case .systemAndMicrophone:
            return AppLocalization.text("Incluye lo que escuchas de todas las aplicaciones y la entrada elegida abajo (micrófono o interfaz). Usa auriculares para evitar eco.")
        case .systemAudio:
            return AppLocalization.text("Incluye lo que reproducen todas las aplicaciones: llamada, música y notificaciones. No captura tu micrófono ni las entradas de tu interfaz.")
        case .microphone:
            return AppLocalization.text("Incluye únicamente el micrófono o los canales de la interfaz elegidos abajo. No captura lo que reproducen las aplicaciones.")
        case .applicationOnly:
            return AppLocalization.text("Incluye lo que reproduce una aplicación. No captura tu entrada de audio; tu voz normalmente no estará incluida. Un navegador puede incluir varias pestañas.")
        case .application:
            return AppLocalization.text("Incluye lo que reproduce una aplicación y la entrada elegida abajo. Usa auriculares para evitar eco. Un navegador puede incluir varias pestañas.")
        }
    }
}

public enum MeetingStatus: String, Codable, Sendable {
    case recording, recorded, transcribing, completed, failed, interrupted
    public var title: String {
        switch self {
        case .recording: return AppLocalization.text("Grabando")
        case .recorded: return AppLocalization.text("Audio guardado")
        case .transcribing: return AppLocalization.text("Transcribiendo")
        case .completed: return AppLocalization.text("Lista")
        case .failed: return AppLocalization.text("Error")
        case .interrupted: return AppLocalization.text("Interrumpida")
        }
    }
}

public enum MeetingStorageLayout: String, Codable, Sendable { case flat }

public struct Meeting: Codable, Identifiable, Equatable, Sendable {
    public var schemaVersion = 1
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var duration: TimeInterval
    public var mode: RecordingMode
    public var sourceApplication: String?
    public var status: MeetingStatus
    public var audioFileName: String
    public var transcript: String?
    public var error: String?
    public var model: String?
    /// Nil for legacy recordings. New recordings keep visible audio/text files flat.
    public var storageLayout: MeetingStorageLayout?

    public init(id: UUID = UUID(), title: String? = nil, mode: RecordingMode, audioFileName: String,
                sourceApplication: String? = nil, status: MeetingStatus = .recorded, createdAt: Date = Date()) {
        self.id = id
        self.title = title ?? Self.automaticTitle(for: createdAt)
        self.createdAt = createdAt
        self.duration = 0
        self.mode = mode
        self.sourceApplication = sourceApplication
        self.status = status
        self.audioFileName = audioFileName
    }

    public static func automaticTitle(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.language.locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd-MM-yyyy HH:mm"
        return AppLocalization.format("Reunión %@", formatter.string(from: date))
    }

    public static func automaticFileStem(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.language.locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        return AppLocalization.format("Reunión %@", formatter.string(from: date))
    }

    public mutating func rename(to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeetingError.message("El nombre de la reunión no puede quedar vacío.") }
        self.title = trimmed
    }
}

public enum MeetingError: LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): return AppLocalization.message(text) }
    }
}

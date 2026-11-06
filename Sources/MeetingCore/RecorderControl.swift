import Darwin
import Foundation

public enum RecorderCommand: String, Codable, Sendable {
    case toggle, stop, show, cancel
}

public struct RecorderStatus: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case idle, preparing, recording, transcribing, error }
    public var state: State
    public var pid: Int32
    public var elapsedSeconds: Int
    public var updatedAt: TimeInterval
    public var language: String?
    public init(state: State, elapsedSeconds: Int = 0) {
        self.state = state
        self.pid = ProcessInfo.processInfo.processIdentifier
        self.elapsedSeconds = elapsedSeconds
        self.updatedAt = Date().timeIntervalSince1970
        self.language = AppLanguage.selected().rawValue
    }
}

private struct ControlRequest: Codable {
    let command: RecorderCommand
    let createdAt: TimeInterval
}

/// User-private, short-lived command queue. No network, shell or arbitrary paths.
public struct RecorderControl: Sendable {
    public let directory: URL
    public var statusURL: URL { directory.appendingPathComponent("status.json") }
    public var requestsURL: URL { directory.appendingPathComponent("Requests", isDirectory: true) }

    public init(directory: URL? = nil) throws {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingRecorder/Control", isDirectory: true)
        try FileManager.default.createDirectory(at: requestsURL, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.directory.path)
    }

    public func send(_ command: RecorderCommand, now: TimeInterval = Date().timeIntervalSince1970) throws {
        let file = requestsURL.appendingPathComponent("\(String(format: "%.6f", now))-\(UUID()).json")
        try JSONEncoder().encode(ControlRequest(command: command, createdAt: now)).write(to: file, options: .atomic)
    }

    public func drain(now: TimeInterval = Date().timeIntervalSince1970) throws -> [RecorderCommand] {
        let files = try FileManager.default.contentsOfDirectory(at: requestsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var commands: [RecorderCommand] = []
        for file in files {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file),
                  let request = try? JSONDecoder().decode(ControlRequest.self, from: data),
                  now >= request.createdAt, now - request.createdAt <= 15 else { continue }
            commands.append(request.command)
        }
        return commands
    }

    public func publish(_ status: RecorderStatus) throws {
        try JSONEncoder().encode(status).write(to: statusURL, options: .atomic)
    }
}

/// The OS releases flock even after crashes. Only the owner runs the GUI/capture.
public final class RecorderInstanceLock {
    private let descriptor: Int32
    public let isOwner: Bool
    public init(directory: URL) throws {
        descriptor = Darwin.open(directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw MeetingError.message("No se pudo abrir el control de instancia.") }
        isOwner = flock(descriptor, LOCK_EX | LOCK_NB) == 0
        if !isOwner, errno != EWOULDBLOCK {
            close(descriptor)
            throw MeetingError.message("No se pudo bloquear la instancia de grabación.")
        }
    }
    deinit { close(descriptor) }
}

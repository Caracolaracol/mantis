import Foundation

enum PermissionResetState: Equatable {
    case idle, running, requiresRestart, failed(String)
}

enum SystemAudioPermissionReset {
    struct Result: Sendable {
        let status: Int32
        let output: String
    }

    typealias Executor = @Sendable (URL, [String]) async throws -> Result
    static let executable = URL(fileURLWithPath: "/usr/bin/tccutil")
    static let arguments = ["reset", "ScreenCapture", "local.agus.MeetingRecorder"]
    static let restartMessage = "Permiso anterior restablecido. Sal de Mantis desde su menú y vuelve a abrir la misma copia de Aplicaciones. Después solicita el acceso al audio del computador y apruébalo en macOS."

    static func reset(execute: Executor = { executable, arguments in
        try await runCommand(executable: executable, arguments: arguments)
    }) async throws {
        let result = try await execute(executable, arguments)
        guard result.status == 0 else {
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "Mantis.PermissionReset", code: Int(result.status), userInfo: [
                NSLocalizedDescriptionKey: detail.isEmpty ? "macOS no pudo restablecer el permiso (código \(result.status))." : detail
            ])
        }
    }

    private static func runCommand(executable: URL, arguments: [String]) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        }.value
    }
}

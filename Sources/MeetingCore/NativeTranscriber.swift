import AVFoundation
import CTranscribe
import Foundation

public final class TranscriptionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

public struct TranscriptResult: Codable, Sendable {
    public let text: String
    public let model: String
    public let engineVersion: String
    public let audioSeconds: Double
    public let chunks: Int
}

/// Serialized native inference. Model/session are created and freed on this actor,
/// never shared with another worker. Cancellation flips only a lock-protected flag.
public actor NativeTranscriber {
    public init() {}
    public nonisolated static var version: String { String(cString: transcribe_version()) }

    public func transcribe(wav: URL, modelURL: URL, cancellation: TranscriptionCancellation,
                           progress: @escaping @Sendable (Double) -> Void = { _ in }) throws -> TranscriptResult {
        guard !cancellation.isCancelled else { throw CancellationError() }
        guard FileManager.default.isReadableFile(atPath: modelURL.path) else {
            throw MeetingError.message("Importa un modelo GGUF en Ajustes antes de transcribir.")
        }
        var session: OpaquePointer?
        try check(transcribe_open(modelURL.path, nil, nil, &session), operation: "Cargar modelo")
        guard let session else { throw MeetingError.message("El motor no creó una sesión.") }
        defer { transcribe_session_free(session) }
        let userdata = Unmanaged.passUnretained(cancellation).toOpaque()
        transcribe_set_abort_callback(session, { pointer in
            guard let pointer else { return false }
            return Unmanaged<TranscriptionCancellation>.fromOpaque(pointer).takeUnretainedValue().isCancelled
        }, userdata)
        let audio = try AVAudioFile(forReading: wav, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard audio.processingFormat.sampleRate == 16_000, audio.processingFormat.channelCount == 1 else {
            throw MeetingError.message("El motor necesita audio mono a 16 kHz.")
        }
        var capabilities = transcribe_capabilities()
        transcribe_capabilities_init(&capabilities)
        try check(transcribe_model_get_capabilities(transcribe_get_model(session), &capabilities), operation: "Consultar modelo")
        let limit = capabilities.max_audio_ms > 0 ? min(20, Double(capabilities.max_audio_ms) / 1000) : 20
        let capacity = AVAudioFrameCount(max(1, Int(limit * 16_000)))
        var pieces: [String] = []
        var chunks = 0
        while audio.framePosition < audio.length {
            guard !cancellation.isCancelled else { throw CancellationError() }
            let start = audio.framePosition
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: capacity) else {
                throw MeetingError.message("No hay memoria para preparar el audio.")
            }
            try audio.read(into: buffer, frameCount: capacity)
            let count = Int(buffer.frameLength)
            guard count > 0, let pcm = buffer.floatChannelData?[0] else { break }
            // Prefer a low-energy boundary near the end rather than cutting a word.
            let used = Self.chunkBoundary(samples: pcm, count: count, hasMore: audio.framePosition < audio.length)
            audio.framePosition = start + Int64(used)
            var params = transcribe_run_params()
            transcribe_run_params_init(&params)
            params.timestamps = TRANSCRIBE_TIMESTAMPS_NONE
            try check(transcribe_run(session, pcm, Int32(used), &params), operation: "Transcribir audio")
            guard !cancellation.isCancelled else { throw CancellationError() }
            let text = String(cString: transcribe_full_text(session)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { pieces.append(text) }
            chunks += 1
            progress(Double(audio.framePosition) / Double(max(1, audio.length)))
        }
        return TranscriptResult(text: pieces.joined(separator: "\n\n"), model: modelURL.lastPathComponent,
                                engineVersion: Self.version, audioSeconds: Double(audio.length) / 16_000, chunks: chunks)
    }

    private func check(_ status: transcribe_status, operation: String) throws {
        if status == TRANSCRIBE_ERR_ABORTED { throw CancellationError() }
        guard status == TRANSCRIBE_OK else {
            throw MeetingError.message("\(operation): \(String(cString: transcribe_status_string(Int32(status.rawValue))))")
        }
    }

    static func chunkBoundary(samples: UnsafePointer<Float>, count: Int, hasMore: Bool) -> Int {
        guard hasMore, count > 32_000 else { return count }
        var best = count
        var energy = Float.greatestFiniteMagnitude
        let window = 1_600 // 100 ms; search the last two seconds, from latest to earliest.
        for end in stride(from: count, through: count - 32_000 + window, by: -window) {
            var sum: Float = 0
            for index in (end - window)..<end { sum += samples[index] * samples[index] }
            if sum < energy { energy = sum; best = end }
        }
        return best
    }
}

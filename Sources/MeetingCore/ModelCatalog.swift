import Foundation
import CryptoKit

public struct CatalogModel: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let details: String
    public let license: String
    public let byteCount: Int64
    public let sha256: String
    public let revision: String
    public var fileName: String { "\(id)-Q8_0.gguf" }
    public var repositoryURL: URL { URL(string: "https://huggingface.co/handy-computer/\(id)-gguf")! }
    public var downloadURL: URL { repositoryURL.appendingPathComponent("resolve/\(revision)/\(fileName)") }
}

/// Verified against transcribe.cpp v0.4.1 docs and HF LFS metadata, 2026-11-04.
/// No network request is made simply by displaying this catalog.
public enum ModelCatalog {
    public static let models: [CatalogModel] = [
        CatalogModel(id: "whisper-base", name: "Whisper Base · Q8",
            details: "Multilingüe, incluye español. Descarga pequeña para comenzar; compara la precisión con tus audios.",
            license: "Apache-2.0 (GGUF)", byteCount: 84_962_880,
            sha256: "81c069428bc8a24551a8169cf31cf09bcfd9d4cf50389ae281323c9aa9648c81",
            revision: "42fcd2077de47c36d779309e0e91b76ec620f56d"),
        CatalogModel(id: "nemotron-3.5-asr-streaming-0.6b", name: "Nemotron 3.5 · Q8",
            details: "Multilingüe, incluye español. Misma familia del modelo local inicial.",
            license: "OpenMDW-1.1", byteCount: 751_094_240,
            sha256: "b94545b313b3223fda7b2857a52681da813935c2127643d1e9ff0c23d988089c",
            revision: "53ce288f69326b415aeef030cfcb02a08a8096dd"),
        CatalogModel(id: "whisper-small", name: "Whisper Small · Q8",
            details: "Multilingüe, incluye español. Alternativa de menor tamaño; precisión por validar en tus reuniones.",
            license: "Apache-2.0 (distribución GGUF); consultar ficha",
            byteCount: 269_751_136,
            sha256: "9b9c8811bbcc82a7766f0fb0925614bdacb0923b2cc630daeac17108b655b860",
            revision: "4afdc7942ecf1997f359deae48a63506b062eac4"),
        CatalogModel(id: "whisper-large-v3-turbo", name: "Whisper Large v3 Turbo · Q8",
            details: "Multilingüe, incluye español. Variante grande de Whisper con decodificador reducido.",
            license: "MIT", byteCount: 886_381_728,
            sha256: "257aa7ec9121c22c167d5e2c49e3e76b4ba0e6e27ebc13074eba0a80f8190220",
            revision: "18ada752005f5fddef499256f9a458d0b37a203a"),
        CatalogModel(id: "granite-speech-4.1-2b-plus", name: "Granite Speech 4.1 Plus · Q8",
            details: "Español, inglés, francés, alemán y portugués. Mantis solo usa transcripción: no activa diarización ni identifica personas.",
            license: "Apache-2.0", byteCount: 2_345_973_280,
            sha256: "2948d80df04531fe68b0e09948b758cd17c12d10648a26c2504eb814172714d6",
            revision: "d511bd6c8ea27005eeb4865ab2545480a3e9541d")
    ]

    public static func matching(_ query: String) -> [CatalogModel] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return models }
        return models.filter { "\($0.name) \($0.details) \($0.license)".localizedStandardContains(query) }
    }

    public static func verify(file: URL, byteCount: Int64, sha256: String) throws {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size.map(Int64.init) == byteCount else {
            throw MeetingError.message("La descarga tiene un tamaño incorrecto. El modelo anterior se conserva.")
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == sha256.lowercased() else {
            throw MeetingError.message("La descarga no pasó la verificación SHA-256. El modelo anterior se conserva.")
        }
    }
}

public struct LocalModel: Identifiable, Sendable {
    public let id: String
    public let name: String
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let update: @Sendable (Double) -> Void
    init(update: @escaping @Sendable (Double) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { update(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) }
    }
}

public actor ModelDownloader {
    public init() {}
    public func download(_ model: CatalogModel, into store: ModelStore,
                         progress: @escaping @Sendable (Double) -> Void) async throws {
        if let available = try store.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, available < model.byteCount * 2 {
            throw MeetingError.message("No hay suficiente espacio libre para descargar y verificar este modelo. Libera al menos el doble de su tamaño.")
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: model.downloadURL, delegate: DownloadProgress(update: progress))
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https" else { throw MeetingError.message("El servidor no entregó el modelo solicitado.") }
        try Task.checkCancellation()
        progress(1)
        try ModelCatalog.verify(file: temporary, byteCount: model.byteCount, sha256: model.sha256)
        try store.installVerifiedModel(from: temporary, model: model)
    }
}

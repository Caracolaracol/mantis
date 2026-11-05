import Foundation

/// Models belong to this app, never to another application's installation/cache.
public struct ModelStore: Sendable {
    public let directory: URL
    public var selectedFileName: String {
        guard let data = try? Data(contentsOf: selectionURL),
              let name = try? JSONDecoder().decode(String.self, from: data),
              name == "default.gguf" || ModelCatalog.models.contains(where: { $0.fileName == name }) else { return "default.gguf" }
        return name
    }
    private var selectionURL: URL { directory.appendingPathComponent("selected-model.json") }
    public var modelURL: URL { directory.appendingPathComponent(selectedFileName) }
    public var isReady: Bool { FileManager.default.isReadableFile(atPath: modelURL.path) }
    public var localModels: [LocalModel] {
        var result: [LocalModel] = []
        if FileManager.default.isReadableFile(atPath: directory.appendingPathComponent("default.gguf").path) {
            result.append(LocalModel(id: "default.gguf", name: "Modelo importado / inicial"))
        }
        result += ModelCatalog.models.filter {
            FileManager.default.isReadableFile(atPath: directory.appendingPathComponent($0.fileName).path)
        }.map { LocalModel(id: $0.fileName, name: $0.name) }
        return result
    }

    public func select(_ fileName: String) throws {
        guard localModels.contains(where: { $0.id == fileName }) else {
            throw MeetingError.message("El modelo seleccionado no está disponible en la biblioteca.")
        }
        try JSONEncoder().encode(fileName).write(to: selectionURL, options: .atomic)
    }

    public init(directory: URL? = nil) throws {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingRecorder/Models", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }

    public func importModel(from source: URL) throws {
        let destination = directory.appendingPathComponent("default.gguf")
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else {
            throw MeetingError.message("Selecciona un modelo GGUF válido y compatible con transcribe.cpp.")
        }
        if source.standardizedFileURL == destination.standardizedFileURL {
            try select("default.gguf")
            return
        }
        let staged = directory.appendingPathComponent("import-\(UUID()).gguf")
        defer { try? FileManager.default.removeItem(at: staged) }
        try FileManager.default.copyItem(at: source, to: staged)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
        } else {
            try FileManager.default.moveItem(at: staged, to: destination)
        }
        try select("default.gguf")
    }

    /// Only called after checksum validation; never replaces the imported model.
    func installVerifiedModel(from source: URL, model: CatalogModel) throws {
        guard ModelCatalog.models.contains(model) else { throw MeetingError.message("Modelo ajeno al catálogo.") }
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else { throw MeetingError.message("La descarga no es GGUF.") }
        let destination = directory.appendingPathComponent(model.fileName)
        let staged = directory.appendingPathComponent("download-\(UUID()).partial")
        defer { try? FileManager.default.removeItem(at: staged) }
        try FileManager.default.copyItem(at: source, to: staged)
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
        } else {
            try FileManager.default.moveItem(at: staged, to: destination)
        }
        // Download does not change the active model; selection is a separate action.
    }
}

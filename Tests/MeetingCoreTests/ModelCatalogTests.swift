import CryptoKit
import XCTest
@testable import MeetingCore

final class ModelCatalogTests: XCTestCase {
    func testModelSearchIsCaseInsensitiveAndIncludesSpanish() {
        XCTAssertEqual(ModelCatalog.matching("WHISPER").count, 3)
        XCTAssertEqual(ModelCatalog.matching("nemotron").first?.id, "nemotron-3.5-asr-streaming-0.6b")
        XCTAssertEqual(ModelCatalog.matching("espanol").count, ModelCatalog.models.count)
        XCTAssertTrue(ModelCatalog.matching("not-a-model").isEmpty)
        XCTAssertEqual(ModelCatalog.matching("   ").count, ModelCatalog.models.count)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ModelCatalogTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testCatalogPinsVersionsSizesAndChecksums() {
        XCTAssertEqual(Set(ModelCatalog.models.map(\.id)).count, ModelCatalog.models.count)
        for model in ModelCatalog.models {
            XCTAssertEqual(model.revision.count, 40)
            XCTAssertEqual(model.sha256.count, 64)
            XCTAssertGreaterThan(model.byteCount, 0)
            XCTAssertEqual(model.downloadURL.scheme, "https")
            XCTAssertEqual(model.downloadURL.host, "huggingface.co")
            XCTAssertTrue(model.downloadURL.path.contains(model.revision))
            XCTAssertTrue(model.fileName.hasSuffix(".gguf"))
        }
    }

    func testChecksumRejectsTruncationAndCorruption() throws {
        let file = try directory().appendingPathComponent("synthetic.gguf")
        let data = Data("GGUF synthetic test data".utf8)
        try data.write(to: file)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try ModelCatalog.verify(file: file, byteCount: Int64(data.count), sha256: hash)
        XCTAssertThrowsError(try ModelCatalog.verify(file: file, byteCount: Int64(data.count + 1), sha256: hash))
        XCTAssertThrowsError(try ModelCatalog.verify(file: file, byteCount: Int64(data.count), sha256: String(repeating: "0", count: 64)))
    }

    func testDownloadedModelDoesNotReplaceOrSelectImportedModel() throws {
        let root = try directory()
        let source = root.appendingPathComponent("source.gguf")
        try Data("GGUF initial".utf8).write(to: source)
        let store = try ModelStore(directory: root.appendingPathComponent("Models"))
        try store.importModel(from: source)
        let original = try Data(contentsOf: store.modelURL)
        let item = try XCTUnwrap(ModelCatalog.models.first)
        try Data("GGUF downloaded fixture".utf8).write(to: source)
        // Exercises only atomic installation, not network or production checksum verification.
        try store.installVerifiedModel(from: source, model: item)
        XCTAssertEqual(store.selectedFileName, "default.gguf")
        XCTAssertEqual(try Data(contentsOf: store.modelURL), original)
        XCTAssertEqual(store.localModels.count, 2)
        try store.select(item.fileName)
        XCTAssertEqual(try ModelStore(directory: store.directory).selectedFileName, item.fileName)
        XCTAssertThrowsError(try store.select("../outside.gguf"))
        XCTAssertThrowsError(try store.select("missing.gguf"))
        XCTAssertEqual(store.selectedFileName, item.fileName)
        try store.importModel(from: source)
        XCTAssertEqual(store.selectedFileName, "default.gguf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(item.fileName).path))
    }

    func testInvalidDownloadPreservesActiveModel() throws {
        let root = try directory()
        let store = try ModelStore(directory: root.appendingPathComponent("Models"))
        let source = root.appendingPathComponent("source.gguf")
        try Data("GGUF initial".utf8).write(to: source)
        try store.importModel(from: source)
        let original = try Data(contentsOf: store.modelURL)
        try Data("not a model".utf8).write(to: source)
        XCTAssertThrowsError(try store.installVerifiedModel(from: source, model: ModelCatalog.models[0]))
        XCTAssertEqual(try Data(contentsOf: store.modelURL), original)
        XCTAssertEqual(store.localModels.count, 1)
    }
}

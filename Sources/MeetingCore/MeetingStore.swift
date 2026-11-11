import Foundation

/// Visible audio/TXT files share a folder by default. Hidden metadata stays private.
public struct MeetingStore: Sendable {
    public let root: URL
    public let textRoot: URL

    public init(root: URL? = nil, textRoot: URL? = nil) throws {
        self.root = root ?? LibraryPreferences.initialRoot()
        self.textRoot = textRoot ?? self.root
        for folder in [self.root, self.textRoot] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
        }
    }

    public func directory(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func directory(for meeting: Meeting) throws -> URL {
        if meeting.storageLayout == .flat {
            return root.appendingPathComponent(".mantis", isDirectory: true)
                .appendingPathComponent(meeting.id.uuidString, isDirectory: true)
        }
        return directory(for: meeting.id)
    }

    /// Called only for a new meeting, never when renaming an existing one.
    public func create(_ meeting: Meeting) throws -> Meeting {
        let existing = try load()
        guard !existing.contains(where: { $0.id == meeting.id }) else { throw MeetingError.message("La reunión ya existe.") }
        let usedStems = Set(existing.filter { $0.storageLayout == .flat }.map {
            URL(fileURLWithPath: $0.audioFileName).deletingPathExtension().lastPathComponent
        })
        let created = try flatVersion(of: meeting, occupiedStems: usedStems)
        try save(created)
        return created
    }

    private func flatVersion(of meeting: Meeting, occupiedStems: Set<String>) throws -> Meeting {
        let base = Meeting.automaticFileStem(for: meeting.createdAt)
        let ext = URL(fileURLWithPath: meeting.audioFileName).pathExtension
        guard !ext.isEmpty else { throw MeetingError.message("El archivo de audio necesita una extensión.") }
        var number = 1
        while true {
            var created = meeting
            let stem = number == 1 ? base : "\(base) (\(number))"
            created.storageLayout = .flat
            created.audioFileName = "\(stem).\(ext)"
            let audio = try audioURL(for: created)
            let text = try transcriptURL(for: created)
            if occupiedStems.contains(stem) || FileManager.default.fileExists(atPath: audio.path)
                || FileManager.default.fileExists(atPath: text.path) {
                number += 1
                continue
            }
            return created
        }
    }

    public func audioURL(for meeting: Meeting) throws -> URL {
        let final = try finalAudioURL(for: meeting)
        let capture = try captureURL(for: meeting)
        if !FileManager.default.fileExists(atPath: final.path), FileManager.default.fileExists(atPath: capture.path) {
            return capture // Recoverable audio if encoding was interrupted or failed.
        }
        return final
    }

    public func captureURL(for meeting: Meeting) throws -> URL {
        try directory(for: meeting).appendingPathComponent("capture.mov")
    }

    public func finalAudioURL(for meeting: Meeting) throws -> URL {
        let name = meeting.audioFileName
        guard !name.isEmpty, name != ".", name != "..", !name.hasPrefix("."),
              !name.contains("/"), !name.contains("\\"), !name.contains("\0") else {
            throw MeetingError.message("Nombre de archivo de audio inválido.")
        }
        let folder = meeting.storageLayout == .flat ? root : try directory(for: meeting)
        return folder.appendingPathComponent(name)
    }

    public func transcriptURL(for meeting: Meeting) throws -> URL {
        let audio = try finalAudioURL(for: meeting)
        if meeting.storageLayout == .flat {
            return textRoot.appendingPathComponent(audio.deletingPathExtension().lastPathComponent + ".txt")
        }
        return try directory(for: meeting).appendingPathComponent("transcript.txt")
    }

    public func save(_ meeting: Meeting) throws {
        _ = try audioURL(for: meeting)
        let folder = try directory(for: meeting)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let manifest = folder.appendingPathComponent("meeting.json")
        if FileManager.default.fileExists(atPath: manifest.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let previous = try decoder.decode(Meeting.self, from: Data(contentsOf: manifest))
            guard previous.id == meeting.id else { throw MeetingError.message("Esta ubicación pertenece a otra grabación.") }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(meeting).write(to: manifest, options: .atomic)
    }

    /// Rename the actual audio and matching TXT as one recoverable operation.
    /// Existing files and names reserved by another recording are never replaced.
    public func renamingRecording(_ meeting: Meeting, toFileStem name: String) throws -> Meeting {
        guard meeting.status != .recording, meeting.status != .transcribing else {
            throw MeetingError.message("Espera a que termine la operación antes de renombrar la reunión.")
        }
        let ext = URL(fileURLWithPath: meeting.audioFileName).pathExtension
        var stem = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if (stem as NSString).pathExtension.lowercased() == ext.lowercased() {
            stem = (stem as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !ext.isEmpty, !stem.isEmpty, stem != ".", stem != "..", !stem.hasPrefix("."),
              !stem.contains("/"), !stem.contains("\\"), !stem.contains(":"),
              stem.rangeOfCharacter(from: .controlCharacters) == nil,
              "\(stem).\(ext)".utf8.count <= 255 else {
            throw MeetingError.message("Usa un nombre de archivo válido, sin barras, dos puntos ni caracteres de control (máximo 255 bytes con extensión).")
        }
        var renamed = meeting
        renamed.audioFileName = "\(stem).\(ext)"
        try renamed.rename(to: stem)
        let sourceAudio = try finalAudioURL(for: meeting)
        guard FileManager.default.fileExists(atPath: sourceAudio.path) else {
            throw MeetingError.message("Esta grabación no tiene audio guardado.")
        }
        if meeting.storageLayout == .flat {
            guard try !load().contains(where: { other in
                other.id != meeting.id && other.storageLayout == .flat
                    && URL(fileURLWithPath: other.audioFileName).deletingPathExtension().lastPathComponent
                        .caseInsensitiveCompare(stem) == .orderedSame
            }) else {
                throw MeetingError.message("Ya existe una grabación o archivo con ese nombre. Elige otro; no se sobrescribió nada.")
            }
        }
        let pairs = [(sourceAudio, try finalAudioURL(for: renamed)),
                     (try transcriptURL(for: meeting), try transcriptURL(for: renamed))]
            .filter { $0.0 != $0.1 }
        // Check both targets, even when a TXT has not been created yet.
        for (_, target) in pairs where FileManager.default.fileExists(atPath: target.path) {
            throw MeetingError.message("Ya existe una grabación o archivo con ese nombre. Elige otro; no se sobrescribió nada.")
        }
        var moved: [(URL, URL)] = []
        do {
            for (source, target) in pairs where FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.moveItem(at: source, to: target)
                moved.append((source, target))
            }
            try save(renamed)
            return renamed
        } catch {
            for (source, target) in moved.reversed() {
                try FileManager.default.moveItem(at: target, to: source)
            }
            throw error
        }
    }

    public func load() throws -> [Meeting] {
        var directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
        let metadata = root.appendingPathComponent(".mantis", isDirectory: true)
        if FileManager.default.fileExists(atPath: metadata.path) {
            directories += try FileManager.default.contentsOfDirectory(at: metadata, includingPropertiesForKeys: nil)
                .filter { UUID(uuidString: $0.lastPathComponent) != nil }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var result: [Meeting] = []
        var identifiers = Set<UUID>()
        for folder in directories {
            let file = folder.appendingPathComponent("meeting.json")
            do {
                var meeting = try decoder.decode(Meeting.self, from: Data(contentsOf: file))
                guard try directory(for: meeting).standardizedFileURL.path == folder.standardizedFileURL.path,
                      meeting.id.uuidString == folder.lastPathComponent, meeting.schemaVersion == 1,
                      identifiers.insert(meeting.id).inserted else {
                    throw MeetingError.message("Identificador o versión de reunión inválidos.")
                }
                _ = try audioURL(for: meeting)
                if meeting.status == .recording || meeting.status == .transcribing {
                    meeting.status = .interrupted
                    meeting.error = "La aplicación se cerró durante una operación. Revisa el audio antes de reintentar."
                    try save(meeting)
                }
                result.append(meeting)
            } catch {
                throw MeetingError.message("No se pudo cargar \(file.path): \(error.localizedDescription)")
            }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    public func delete(_ meeting: Meeting) throws {
        if meeting.storageLayout == .flat {
            for url in [try audioURL(for: meeting), try transcriptURL(for: meeting)] {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
        }
        try FileManager.default.removeItem(at: directory(for: meeting))
    }

    /// Explicit library copy: preserves originals, rejects conflicts, stages before commit.
    public func copyingLibrary(to destination: URL, keepingTextFolder: Bool = false) throws -> MeetingStore {
        let source = root.resolvingSymlinksInPath().standardizedFileURL
        let target = destination.resolvingSymlinksInPath().standardizedFileURL
        if source.path == target.path { return self }
        guard !target.path.hasPrefix(source.path + "/"), !source.path.hasPrefix(target.path + "/"), target.path != "/" else {
            throw MeetingError.message("Elige una carpeta independiente de la biblioteca actual.")
        }
        let meetings = try load()
        let result = try MeetingStore(root: target, textRoot: keepingTextFolder ? textRoot : nil)
        let existingIDs = Set(try result.load().map(\.id))
        for meeting in meetings {
            let folder = try result.directory(for: meeting)
            guard !existingIDs.contains(meeting.id), !FileManager.default.fileExists(atPath: folder.path) else {
                throw MeetingError.message("La carpeta de destino ya contiene una reunión con el mismo identificador. No se sobrescribió nada.")
            }
            let values = try directory(for: meeting).resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw MeetingError.message("No se puede copiar una reunión que es un enlace simbólico.") }
            if meeting.storageLayout == .flat {
                for file in [try result.finalAudioURL(for: meeting), try result.transcriptURL(for: meeting)] {
                    if keepingTextFolder, file == (try result.transcriptURL(for: meeting)) { continue }
                    guard !FileManager.default.fileExists(atPath: file.path) else { throw MeetingError.message("Ya existe un archivo con ese nombre en el destino. No se sobrescribió nada.") }
                }
            }
        }
        let staging = target.appendingPathComponent(".mantis-copy-\(UUID())", isDirectory: true)
        let staged = try MeetingStore(root: staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        var moves: [(URL, URL)] = []
        for meeting in meetings {
            moves.append((try staged.directory(for: meeting), try result.directory(for: meeting)))
            let stagedFolder = try staged.directory(for: meeting)
            try FileManager.default.createDirectory(at: stagedFolder.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            try FileManager.default.copyItem(at: directory(for: meeting), to: stagedFolder)
            if meeting.storageLayout == .flat {
                for (original, temporary, final) in [
                    (try finalAudioURL(for: meeting), try staged.finalAudioURL(for: meeting), try result.finalAudioURL(for: meeting)),
                    (try transcriptURL(for: meeting), try staged.transcriptURL(for: meeting), try result.transcriptURL(for: meeting))
                ] where original.standardizedFileURL != final.standardizedFileURL && FileManager.default.fileExists(atPath: original.path) {
                    try FileManager.default.copyItem(at: original, to: temporary)
                    moves.append((temporary, final))
                }
            }
        }
        _ = try staged.load()
        var committed: [URL] = []
        do {
            for (temporary, final) in moves {
                try FileManager.default.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                       attributes: [.posixPermissions: 0o700])
                try FileManager.default.moveItem(at: temporary, to: final)
                committed.append(final)
            }
            _ = try result.load()
            return result
        } catch {
            for file in committed { try? FileManager.default.removeItem(at: file) }
            throw error
        }
    }

    /// Post-setup option. Copies TXT files without deleting old copies or touching audio.
    public func copyingTranscripts(to destination: URL) throws -> MeetingStore {
        let target = destination.resolvingSymlinksInPath().standardizedFileURL
        if target.path == textRoot.resolvingSymlinksInPath().standardizedFileURL.path { return self }
        let result = try MeetingStore(root: root, textRoot: target)
        var pairs: [(URL, URL)] = []
        for meeting in try load() where meeting.storageLayout == .flat {
            let source = try transcriptURL(for: meeting)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let final = try result.transcriptURL(for: meeting)
            if FileManager.default.fileExists(atPath: final.path) {
                if FileManager.default.contentsEqual(atPath: source.path, andPath: final.path) { continue }
                throw MeetingError.message("Ya existe un texto diferente con ese nombre en el destino. No se sobrescribió nada.")
            }
            pairs.append((source, final))
        }
        let staging = target.appendingPathComponent(".mantis-text-copy-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        var committed: [URL] = []
        do {
            for (source, final) in pairs { try FileManager.default.copyItem(at: source, to: staging.appendingPathComponent(final.lastPathComponent)) }
            for (_, final) in pairs {
                try FileManager.default.moveItem(at: staging.appendingPathComponent(final.lastPathComponent), to: final)
                committed.append(final)
            }
            return result
        } catch {
            for file in committed { try? FileManager.default.removeItem(at: file) }
            throw error
        }
    }

    /// Explicit conversion of old UUID folders. Originals are retained as hidden backups.
    public func consolidatingLegacyRecordings() throws -> MeetingStore {
        let meetings = try load()
        let legacy = meetings.filter { $0.storageLayout == nil }
        guard !legacy.isEmpty else { return self }
        var used = Set(meetings.filter { $0.storageLayout == .flat }.map {
            URL(fileURLWithPath: $0.audioFileName).deletingPathExtension().lastPathComponent
        })
        let staging = root.appendingPathComponent(".mantis-organize-\(UUID())", isDirectory: true)
        let staged = try MeetingStore(root: staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        var moves: [(URL, URL)] = []
        var backups: [(URL, URL)] = []
        for old in legacy {
            let sourceFolder = try directory(for: old)
            guard try sourceFolder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw MeetingError.message("No se puede organizar una grabación que es un enlace simbólico.")
            }
            let updated = try flatVersion(of: old, occupiedStems: used)
            used.insert(URL(fileURLWithPath: updated.audioFileName).deletingPathExtension().lastPathComponent)
            let backup = root.appendingPathComponent(".mantis/PreviousFolders", isDirectory: true)
                .appendingPathComponent(old.id.uuidString, isDirectory: true)
            let finalMetadata = try directory(for: updated)
            guard !FileManager.default.fileExists(atPath: backup.path),
                  !FileManager.default.fileExists(atPath: finalMetadata.path) else {
                throw MeetingError.message("Ya existe una copia interna de esta grabación. No se modificó la carpeta anterior.")
            }
            try staged.save(updated)
            moves.append((try staged.directory(for: updated), finalMetadata))
            backups.append((sourceFolder, backup))
            for (source, temporary, final) in [
                (try audioURL(for: old), try staged.audioURL(for: updated), try audioURL(for: updated)),
                (try transcriptURL(for: old), try staged.transcriptURL(for: updated), try transcriptURL(for: updated))
            ] where FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: temporary)
                moves.append((temporary, final))
            }
            let json = sourceFolder.appendingPathComponent("transcript.json")
            if FileManager.default.fileExists(atPath: json.path) {
                try FileManager.default.copyItem(at: json, to: staged.directory(for: updated).appendingPathComponent("transcript.json"))
            }
        }
        _ = try staged.load()
        var committed: [URL] = []
        var backedUp: [(URL, URL)] = []
        do {
            for (temporary, final) in moves {
                try FileManager.default.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                       attributes: [.posixPermissions: 0o700])
                try FileManager.default.moveItem(at: temporary, to: final)
                committed.append(final)
            }
            for (original, backup) in backups {
                try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                       attributes: [.posixPermissions: 0o700])
                try FileManager.default.moveItem(at: original, to: backup)
                backedUp.append((original, backup))
            }
            _ = try load()
            return self
        } catch {
            for (original, backup) in backedUp.reversed() { try? FileManager.default.moveItem(at: backup, to: original) }
            for file in committed { try? FileManager.default.removeItem(at: file) }
            throw error
        }
    }
}

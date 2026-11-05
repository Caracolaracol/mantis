import AVFoundation
import AppKit
import Combine
import MeetingCore
import ScreenCaptureKit

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published private(set) var meetings: [Meeting] = []
    @Published var selection: UUID?
    @Published var settingsPage: MantisSettingsPage = .general
    @Published var mode = RecordingMode(rawValue: UserDefaults.standard.string(forKey: "recordingMode") ?? "") ?? .systemAndMicrophone {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "recordingMode") }
    }
    @Published var automaticTranscription = RecordingPreferences.automaticTranscription() {
        didSet { RecordingPreferences.setAutomaticTranscription(automaticTranscription) }
    }
    @Published var selectedApplicationID: Int32?
    @Published private(set) var applications: [SCRunningApplication] = []
    @Published private(set) var audioInputs: [AudioInputDevice] = []
    @Published var selectedAudioInputUID = UserDefaults.standard.string(forKey: "audioInputUID") ?? "" {
        didSet {
            UserDefaults.standard.set(selectedAudioInputUID, forKey: "audioInputUID")
            selectedInputChannels = [0]
        }
    }
    @Published var selectedInputChannels = Set((UserDefaults.standard.array(forKey: "audioInputChannels") as? [Int]) ?? [0]) {
        didSet { UserDefaults.standard.set(selectedInputChannels.sorted(), forKey: "audioInputChannels") }
    }
    @Published private(set) var activeMeetingID: UUID?
    @Published private(set) var processingID: UUID?
    @Published private(set) var preparing = false
    @Published private(set) var loadingApplications = false
    @Published private(set) var phase = ""
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var microphoneLevel: Double = 0
    @Published var alert: String?
    @Published private(set) var permissionSnapshot = CaptureAuthorizationSnapshot(microphone: .notRequested, systemAudio: .unverified)
    @Published private(set) var localModels: [LocalModel] = []
    @Published private(set) var selectedModelFileName = "default.gguf"
    @Published private(set) var modelDownloadID: String?
    @Published private(set) var modelDownloadProgress: Double = 0
    @Published private(set) var modelDownloadError: String?
    @Published var showingOnboarding = !LibraryPreferences.setupCompleted()
    @Published private(set) var configuringPermissions = false
    @Published private(set) var permissionSetupMessage: String?
    @Published private(set) var systemAudioPermissionResetState: PermissionResetState = .idle

    @Published private(set) var store: MeetingStore?
    let models: ModelStore?
    private let recorder = RecordingService()
    private let normalizer = AudioNormalizer()
    private let transcriber = NativeTranscriber()
    private var pipelineTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var startedAt: Date?
    private var stopping = false
    private var modelDownloadTask: Task<Void, Never>?
    private var isPreview = false

    var busy: Bool { preparing || configuringPermissions || systemAudioPermissionResetState == .running || activeMeetingID != nil || processingID != nil || modelDownloadID != nil }
    var selectedMeeting: Meeting? { meetings.first { $0.id == selection } }
    var inputRoute: AudioInputRoute? {
        selectedAudioInputUID.isEmpty ? nil : AudioInputRoute(deviceUID: selectedAudioInputUID, channels: selectedInputChannels.sorted())
    }

    init(preview: Bool = false) {
        if preview {
            isPreview = true
            models = nil
            store = nil
            showingOnboarding = false
            let sample = Meeting(title: "Planificación del equipo", mode: .systemAndMicrophone, audioFileName: "Reunión.m4a", status: .completed)
            var ready = sample
            ready.duration = 1475
            ready.transcript = "Revisamos los avances de la semana y acordamos las prioridades del próximo ciclo.\n\nEl equipo preparará una propuesta con los cambios discutidos. La próxima revisión será el viernes."
            meetings = [ready, Meeting(title: "Revisión de proyecto", mode: .systemAudio, audioFileName: "Audio.m4a")]
            selection = ready.id
            permissionSnapshot = CaptureAuthorizationSnapshot(microphone: .allowed, systemAudio: .allowed)
            return
        }
        models = try? ModelStore()
        do {
            let store = try MeetingStore(textRoot: LibraryPreferences.transcriptRoot())
            self.store = store
            do { meetings = try store.load(); selection = meetings.first?.id }
            catch { alert = error.localizedDescription }
        } catch {
            self.store = nil
            alert = error.localizedDescription
        }
        refreshModels()
        refreshPermissions()
    }

    func refreshPermissions() {
        guard !isPreview else { return }
        permissionSnapshot = PermissionService.snapshot()
        if systemAudioPermissionResetState == .requiresRestart {
            permissionSnapshot = CaptureAuthorizationSnapshot(microphone: permissionSnapshot.microphone, systemAudio: .unverified)
        }
    }

    func refreshAudioInputs() {
        guard !busy, !isPreview else { return }
        do { audioInputs = try AudioInputDevice.available() }
        catch { alert = error.localizedDescription }
    }

    func openPermissionSettings(_ kind: CapturePermissionKind) {
        PermissionService.openSettings(kind)
    }

    func loadApplications() {
        guard !busy, !loadingApplications else { return }
        loadingApplications = true
        Task {
            defer { loadingApplications = false }
            do {
                applications = try await recorder.applications()
                if !applications.contains(where: { $0.processID == selectedApplicationID }) {
                    selectedApplicationID = nil
                }
            } catch { alert = error.localizedDescription }
        }
    }

    /// A deliberate click on a quick-access button starts whole-computer audio + mic.
    /// System permissions are still required; no participant checkbox blocks recording.
    func toggleQuickRecording() {
        if activeMeetingID != nil { stopRecording(); return }
        guard !busy, !loadingApplications, !showingOnboarding else { return }
        mode = .systemAndMicrophone
        startRecording()
    }

    var recorderStatus: RecorderStatus {
        let state: RecorderStatus.State
        if activeMeetingID != nil { state = .recording }
        else if processingID != nil { state = .transcribing }
        else if preparing || configuringPermissions || systemAudioPermissionResetState == .running || modelDownloadID != nil { state = .preparing }
        else if alert != nil { state = .error }
        else { state = .idle }
        return RecorderStatus(state: state, elapsedSeconds: Int(max(0, elapsed)))
    }

    func startRecording() {
        guard !busy, !loadingApplications, let store else { return }
        if mode.capturesScreenAudio, systemAudioPermissionResetState == .requiresRestart {
            alert = SystemAudioPermissionReset.restartMessage
            return
        }
        if mode.capturesApplication && selectedApplicationID == nil {
            alert = "Selecciona la aplicación en Ajustes → Grabación antes de empezar."
            return
        }
        let mode = mode
        let route = mode.capturesMicrophone ? inputRoute : nil
        let appID = selectedApplicationID
        let appName = applications.first { $0.processID == appID }?.applicationName
        var meeting = Meeting(mode: mode, audioFileName: "audio.m4a",
                              sourceApplication: mode.capturesWholeSystemAudio ? "Todo el computador" : (mode.capturesApplication ? appName : nil), status: .recording)
        preparing = true
        Task {
            defer { preparing = false }
            do {
                meeting = try store.create(meeting)
                if automaticTranscription { try requireModel() }
                try persist(meeting)
                selection = meeting.id
                let destination = mode == .microphone && route == nil ? try store.finalAudioURL(for: meeting) : try store.captureURL(for: meeting)
                try await recorder.start(mode: mode, applicationID: appID, destination: destination, route: route) { [weak self] message in
                    self?.stopRecording(captureError: message)
                }
                refreshPermissions()
                activeMeetingID = meeting.id
                startedAt = Date()
                elapsed = 0
                if let failure = recorder.captureFailure { stopRecording(captureError: failure) }
                else { startTimer() }
            } catch {
                meeting.status = .failed
                let message = CaptureErrorPresentation.message(for: error)
                meeting.error = message
                saveOrReport(meeting)
                alert = message
                refreshPermissions()
            }
        }
    }

    func requestConfiguredPermissions() async {
        guard !busy, !configuringPermissions else { return }
        if mode.capturesScreenAudio, systemAudioPermissionResetState == .requiresRestart {
            permissionSetupMessage = SystemAudioPermissionReset.restartMessage
            return
        }
        configuringPermissions = true
        permissionSetupMessage = nil
        defer { configuringPermissions = false; refreshPermissions() }
        do { try await recorder.preparePermissions(for: mode) }
        catch { permissionSetupMessage = CaptureErrorPresentation.message(for: error) }
    }

    func resetSystemAudioPermission(using reset: @Sendable () async throws -> Void = { try await SystemAudioPermissionReset.reset() }) async {
        guard !busy, !loadingApplications, systemAudioPermissionResetState != .requiresRestart else { return }
        systemAudioPermissionResetState = .running
        do {
            try await reset()
            systemAudioPermissionResetState = .requiresRestart
            permissionSnapshot = CaptureAuthorizationSnapshot(microphone: permissionSnapshot.microphone, systemAudio: .unverified)
            permissionSetupMessage = SystemAudioPermissionReset.restartMessage
        } catch {
            systemAudioPermissionResetState = .failed(error.localizedDescription)
        }
    }

    func useLibrary(at root: URL, keepingTextFolder: Bool = false) async throws {
        guard !busy, !loadingApplications else { throw MeetingError.message("Espera a que termine la operación antes de cambiar de carpeta.") }
        preparing = true
        defer { preparing = false }
        let previous = store
        let previousSelection = selection
        let updated = try await Task.detached(priority: .userInitiated) {
            if let previous {
                let copied = try previous.copyingLibrary(to: root, keepingTextFolder: keepingTextFolder)
                return try copied.consolidatingLegacyRecordings()
            }
            return try MeetingStore(root: root)
        }.value
        let loaded = try updated.load()
        LibraryPreferences.setRoot(updated.root)
        saveTextLocationPreference(updated)
        store = updated
        meetings = loaded
        selection = loaded.contains(where: { $0.id == previousSelection }) ? previousSelection : loaded.first?.id
    }

    func useTextFolder(at root: URL) async throws {
        guard !busy, !loadingApplications, let current = store else {
            throw MeetingError.message("Espera a que termine la operación antes de cambiar de carpeta.")
        }
        preparing = true
        defer { preparing = false }
        let updated = try await Task.detached(priority: .userInitiated) {
            try current.copyingTranscripts(to: root)
        }.value
        saveTextLocationPreference(updated)
        store = updated
    }

    func consolidateRecordings() async throws {
        guard !busy, !loadingApplications, let current = store else {
            throw MeetingError.message("Espera a que termine la operación antes de organizar las grabaciones.")
        }
        preparing = true
        defer { preparing = false }
        let updated = try await Task.detached(priority: .userInitiated) {
            try current.consolidatingLegacyRecordings()
        }.value
        let loaded = try updated.load()
        store = updated
        meetings = loaded
    }

    private func saveTextLocationPreference(_ store: MeetingStore) {
        let same = store.root.resolvingSymlinksInPath().path == store.textRoot.resolvingSymlinksInPath().path
        LibraryPreferences.setTranscriptRoot(same ? nil : store.textRoot)
    }

    func finishOnboarding(transcription: OnboardingTranscriptionChoice) throws {
        guard !busy else { throw MeetingError.message("Espera a que termine la operación antes de completar la configuración.") }
        automaticTranscription = try transcription.apply(to: models)
        refreshModels()
        LibraryPreferences.completeSetup()
        showingOnboarding = false
    }

    func stopRecording(captureError: String? = nil) {
        guard let id = activeMeetingID, !stopping else { return }
        stopping = true
        preparing = true
        timerTask?.cancel()
        timerTask = nil
        Task {
            var failure = captureError
            do { try await recorder.stop() }
            catch { failure = failure ?? error.localizedDescription }
            activeMeetingID = nil
            microphoneLevel = 0
            defer {
                preparing = false
                stopping = false
                if processingID == nil { phase = "" }
            }
            guard var meeting = meetings.first(where: { $0.id == id }), let store else { return }
            meeting.duration = Date().timeIntervalSince(startedAt ?? Date())
            let capture = try? store.captureURL(for: meeting)
            var converted = false
            if let capture, FileManager.default.fileExists(atPath: capture.path) {
                phase = "Guardando audio M4A…"
                do {
                    meeting.duration = try await normalizer.exportM4A(source: capture, destination: store.finalAudioURL(for: meeting))
                    converted = true
                } catch {
                    failure = failure ?? "No se pudo guardar el M4A: \(error.localizedDescription) El audio temporal se conserva y puedes escucharlo."
                }
            }
            meeting.status = failure == nil ? .recorded : .failed
            meeting.error = failure
            do { try persist(meeting) }
            catch { alert = error.localizedDescription; return }
            if converted, failure == nil, let capture { try? FileManager.default.removeItem(at: capture) }
            preparing = false
            stopping = false
            if let failure { alert = failure }
            else if automaticTranscription { transcribe(id) }
        }
    }

    func importAudio(_ source: URL) {
        guard !busy, !loadingApplications, let store else { return }
        preparing = true
        var meeting = Meeting(mode: .microphone,
                              audioFileName: "audio.m4a",
                              sourceApplication: "Archivo importado", status: .recording)
        Task {
            defer { preparing = false }
            do {
                meeting = try store.create(meeting)
                if automaticTranscription { try requireModel() }
                try persist(meeting)
                selection = meeting.id
                let destination = try store.audioURL(for: meeting)
                meeting.duration = try await normalizer.exportM4A(source: source, destination: destination)
                meeting.status = .recorded
                try persist(meeting)
                preparing = false
                if automaticTranscription { transcribe(meeting.id) }
            } catch {
                meeting.status = .failed
                meeting.error = error.localizedDescription
                saveOrReport(meeting)
                alert = error.localizedDescription
            }
        }
    }

    func transcribe(_ id: UUID) {
        guard !busy, !loadingApplications, let store,
              var meeting = meetings.first(where: { $0.id == id }) else { return }
        do {
            try requireModel()
            meeting.status = .transcribing
            meeting.error = nil
            try persist(meeting)
        } catch { alert = error.localizedDescription; return }
        processingID = id
        phase = "Preparando audio…"
        let cancellation = TranscriptionCancellation()
        pipelineTask = Task {
            defer { processingID = nil; pipelineTask = nil; phase = "" }
            do {
                let directory = try store.directory(for: meeting)
                let source = try store.audioURL(for: meeting)
                let wav = directory.appendingPathComponent("normalized.wav")
                let result = try await withTaskCancellationHandler {
                    _ = try await normalizer.normalize(source: source, destination: wav)
                    try Task.checkCancellation()
                    phase = "Transcribiendo localmente…"
                    return try await transcriber.transcribe(wav: wav, modelURL: models!.modelURL, cancellation: cancellation) { [weak self] progress in
                        Task { @MainActor in
                            guard self?.processingID == id else { return }
                            self?.phase = "Transcribiendo localmente… \(Int(progress * 100)) %"
                        }
                    }
                } onCancel: { cancellation.cancel() }
                try JSONEncoder().encode(result).write(to: directory.appendingPathComponent("transcript.json"), options: .atomic)
                try result.text.write(to: store.transcriptURL(for: meeting), atomically: true, encoding: .utf8)
                meeting.transcript = result.text
                meeting.model = result.model
                meeting.duration = result.audioSeconds
                meeting.status = .completed
                meeting.error = nil
                try persist(meeting)
                // Intermediate PCM is reproducible; retain the small original, not 115 MB/h of WAV.
                try? FileManager.default.removeItem(at: wav)
            } catch is CancellationError {
                meeting.status = .recorded
                meeting.error = "Transcripción cancelada. El audio original se conserva."
                saveOrReport(meeting)
            } catch {
                meeting.status = .failed
                meeting.error = error.localizedDescription
                saveOrReport(meeting)
                alert = error.localizedDescription
            }
        }
    }

    func cancelTranscription() { pipelineTask?.cancel() }

    func deleteSelected() {
        guard !busy, let store, let meeting = selectedMeeting else { return }
        do {
            try store.delete(meeting)
            meetings.removeAll { $0.id == meeting.id }
            selection = meetings.first?.id
        } catch { alert = error.localizedDescription }
    }

    func renameMeeting(_ id: UUID, to title: String) throws {
        guard !busy, var meeting = meetings.first(where: { $0.id == id }) else {
            throw MeetingError.message("Espera a que termine la operación antes de renombrar la reunión.")
        }
        try meeting.rename(to: title)
        try persist(meeting)
    }

    func reveal(_ meeting: Meeting) {
        guard let store else { return }
        do {
            let url = try store.audioURL(for: meeting)
            guard FileManager.default.fileExists(atPath: url.path) else { throw MeetingError.message("Esta grabación no tiene audio guardado.") }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        catch { alert = error.localizedDescription }
    }

    func openLibraryFolder() {
        guard let store else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: store.root.path)
    }

    func revealTranscript(_ meeting: Meeting) {
        guard let store else { return }
        do {
            let url = try store.transcriptURL(for: meeting)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw MeetingError.message("Esta grabación todavía no tiene un archivo TXT guardado.")
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { alert = error.localizedDescription }
    }

    func openAudio(_ meeting: Meeting) {
        guard let store else { return }
        do {
            let url = try store.audioURL(for: meeting)
            guard FileManager.default.fileExists(atPath: url.path) else { throw MeetingError.message("Esta grabación no tiene audio guardado. Revisa el aviso o los permisos de captura.") }
            NSWorkspace.shared.open(url)
        }
        catch { alert = error.localizedDescription }
    }

    func importModel(_ source: URL, onSuccess: (@MainActor () -> Void)? = nil,
                     onFailure: (@MainActor (String) -> Void)? = nil) {
        guard !busy, let models else { return }
        preparing = true
        Task {
            defer { preparing = false }
            do {
                try await Task.detached(priority: .userInitiated) { try models.importModel(from: source) }.value
                refreshModels()
                onSuccess?()
            } catch {
                if let onFailure { onFailure(error.localizedDescription) }
                else { alert = error.localizedDescription }
            }
        }
    }

    func refreshModels() {
        localModels = models?.localModels ?? []
        selectedModelFileName = models?.selectedFileName ?? "default.gguf"
    }

    func selectModel(_ fileName: String) {
        guard !busy, let models else { return }
        do { try models.select(fileName); refreshModels() }
        catch { alert = error.localizedDescription }
    }

    /// Call only after the user confirms the model, size and remote source.
    func downloadModel(_ item: CatalogModel) {
        guard !busy, let models else { return }
        modelDownloadID = item.id
        modelDownloadProgress = 0
        modelDownloadError = nil
        modelDownloadTask = Task {
            defer { modelDownloadID = nil; modelDownloadTask = nil; modelDownloadProgress = 0 }
            do {
                try await ModelDownloader().download(item, into: models) { [weak self] progress in
                    Task { @MainActor in
                        guard self?.modelDownloadID == item.id else { return }
                        self?.modelDownloadProgress = progress
                    }
                }
                refreshModels()
            } catch {
                if !Task.isCancelled { modelDownloadError = error.localizedDescription }
            }
        }
    }

    func cancelModelDownload() { modelDownloadTask?.cancel() }

    private func requireModel() throws {
        guard models?.isReady == true else {
            throw MeetingError.message("Selecciona, importa o descarga un modelo en Ajustes para transcribir. Con transcripción automática desactivada puedes grabar sin modelo.")
        }
    }

    private func persist(_ meeting: Meeting) throws {
        guard let store else { throw MeetingError.message("El almacenamiento local no está disponible.") }
        try store.save(meeting)
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) { meetings[index] = meeting }
        else { meetings.insert(meeting, at: 0) }
    }

    private func saveOrReport(_ meeting: Meeting) {
        do { try persist(meeting) }
        catch { alert = error.localizedDescription }
    }

    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.elapsed = Date().timeIntervalSince(self.startedAt ?? Date())
                self.microphoneLevel = self.recorder.microphoneLevel
                if self.mode == .microphone && self.inputRoute == nil && !self.recorder.microphoneIsRecording {
                    self.stopRecording(captureError: "El micrófono dejó de grabar inesperadamente.")
                    return
                }
                do { try await Task.sleep(nanoseconds: 200_000_000) }
                catch { return }
            }
        }
    }
}

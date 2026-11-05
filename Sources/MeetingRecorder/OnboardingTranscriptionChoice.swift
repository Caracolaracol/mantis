import MeetingCore

/// A detected model is offered explicitly, not silently accepted by the setup step.
struct OnboardingTranscriptionChoice {
    var modelFileName: String? {
        didSet { if modelFileName == nil { automaticTranscription = false } }
    }
    var automaticTranscription: Bool

    init(activeFileName: String, availableFileNames: [String], automaticTranscription: Bool) {
        modelFileName = availableFileNames.contains(activeFileName) ? activeFileName : nil
        self.automaticTranscription = modelFileName != nil && automaticTranscription
    }

    var confirmationTitle: String {
        modelFileName == nil ? "Abrir Mantis (solo audio)" : "Usar modelo y abrir Mantis"
    }

    func apply(to store: ModelStore?) throws -> Bool {
        guard let modelFileName else { return false }
        guard let store else { throw MeetingError.message("La biblioteca de modelos no está disponible.") }
        try store.select(modelFileName)
        return automaticTranscription
    }
}

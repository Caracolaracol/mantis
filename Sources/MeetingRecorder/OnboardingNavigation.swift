import Combine

/// Keeps folder selection and the primary Continue action in a single flow.
@MainActor
final class OnboardingNavigation: ObservableObject {
    @Published private(set) var step = 0
    @Published private(set) var advancing = false

    init(step: Int = 0) {
        precondition((0...3).contains(step))
        self.step = step
    }

    func primaryTitle(changingLibrary: Bool) -> String {
        if step == 1, advancing { return "Guardando carpeta…" }
        if step == 1, changingLibrary { return "Usar carpeta y continuar" }
        return step == 3 ? "Abrir Mantis" : "Continuar"
    }

    func back() {
        guard !advancing else { return }
        step = max(0, step - 1)
    }

    func advance(applyLibrary: () async throws -> Void, finish: () throws -> Void) async throws {
        guard !advancing else { return }
        advancing = true
        defer { advancing = false }
        if step == 1 { try await applyLibrary() }
        if step == 3 { try finish() }
        else { step += 1 }
    }
}

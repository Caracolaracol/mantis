import AppKit
import MeetingCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @StateObject private var navigation: OnboardingNavigation
    @State private var library: URL
    @State private var error: String?
    @State private var transcriptionChoice: OnboardingTranscriptionChoice
    @Environment(\.scenePhase) private var scenePhase
    private let steps = ["Audio", "Carpeta", "Permisos", "Transcripción"]
    private var step: Int { navigation.step }

    init(model: AppModel, initialStep: Int = 0) {
        self.model = model
        _navigation = StateObject(wrappedValue: OnboardingNavigation(step: initialStep))
        _library = State(initialValue: LibraryPreferences.setupCompleted()
            ? (model.store?.root ?? LibraryPreferences.suggestedRoot()) : LibraryPreferences.suggestedRoot())
        _transcriptionChoice = State(initialValue: OnboardingTranscriptionChoice(
            activeFileName: model.selectedModelFileName, availableFileNames: model.localModels.map(\.id),
            automaticTranscription: model.automaticTranscription))
    }

    private var libraryApplied: Bool {
        library.resolvingSymlinksInPath().standardizedFileURL.path == model.store?.root.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private var inputValid: Bool {
        guard model.mode.capturesMicrophone, let route = model.inputRoute else { return true }
        guard let device = model.audioInputs.first(where: { $0.id == route.deviceUID }) else { return false }
        return (try? route.validate(channelCount: device.channelCount)) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        MantisBrandMark(size: 30)
                        Text("Mantis").font(.title.bold()).foregroundStyle(MantisTheme.pink)
                    }
                    Text("Tu espacio privado para escuchar y recordar.")
                        .font(.callout).foregroundStyle(MantisTheme.secondary)
                }
                Spacer()
                Text("Paso \(step + 1) de \(steps.count)").font(.caption.weight(.semibold)).foregroundStyle(MantisTheme.green)
                    .padding(.horizontal, 11).padding(.vertical, 7).background(MantisTheme.green.opacity(0.08), in: Capsule())
            }
            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(index <= step ? MantisTheme.green : MantisTheme.border).frame(height: 3)
                        Text(steps[index]).font(.caption).foregroundStyle(index == step ? MantisTheme.pink : MantisTheme.secondary)
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case 0: audioStep
                    case 1: libraryStep
                    case 2: permissionStep
                    default: transcriptionStep
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).mantisCard()
            }
            HStack {
                Button("Ahora no") { model.showingOnboarding = false }.disabled(model.busy || navigation.advancing)
                Spacer()
                if step > 0 {
                    Button("Atrás") { error = nil; navigation.back() }.disabled(model.busy || navigation.advancing)
                }
                Button(step == 3 ? transcriptionChoice.confirmationTitle : navigation.primaryTitle(changingLibrary: !libraryApplied)) {
                    error = nil
                    Task {
                        do {
                            try await navigation.advance(applyLibrary: {
                                if !libraryApplied { try await model.useLibrary(at: library) }
                            }, finish: { try model.finishOnboarding(transcription: transcriptionChoice) })
                        } catch { self.error = error.localizedDescription }
                    }
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(MantisTheme.background)
                .disabled(model.busy || navigation.advancing || (step == 0 && !inputValid))
            }
        }
        .padding(28).frame(width: 760, height: 720).mantisAppearance()
        .onAppear { model.refreshAudioInputs(); model.refreshPermissions() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refreshPermissions() } }
    }

    private var audioStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("¿Qué quieres grabar?").font(.title2.bold())
            Text("Son dos fuentes distintas. Elige ambas para guardar una llamada y tu voz.")
                .foregroundStyle(MantisTheme.secondary)
            Label("Computador: lo que reproducen las aplicaciones, como las voces de la llamada.", systemImage: "desktopcomputer")
            Label("Entrada: tu micrófono o los canales de una interfaz de audio.", systemImage: "mic")
            Picker("Grabación habitual", selection: $model.mode) {
                Text("Todo: computador + entrada (recomendado)").tag(RecordingMode.systemAndMicrophone)
                Text("Solo computador").tag(RecordingMode.systemAudio)
                Text("Solo entrada de audio").tag(RecordingMode.microphone)
                if model.mode.capturesApplication { Text("Una aplicación · ajustar al grabar").tag(model.mode) }
            }.disabled(model.busy)
            if model.mode.capturesMicrophone { AudioInputPicker(model: model) }
            if !inputValid { Text("Selecciona una entrada disponible y al menos un canal.").foregroundStyle(.red).font(.caption) }
            Text("Puedes cambiar fuentes y modos desde Ajustes → Grabación. Aquí no se inicia ninguna captura.")
                .font(.caption).foregroundStyle(MantisTheme.secondary)
        }
    }

    private var libraryStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("¿Dónde guardamos tus grabaciones?").font(.title2.bold())
            Text("Todos los audios y textos juntos en esta carpeta, sin subcarpetas por reunión. Cada par de archivos lleva fecha y hora.")
                .foregroundStyle(MantisTheme.secondary)
            Label("Carpeta elegida: \(library.lastPathComponent)", systemImage: "folder.fill").font(.headline).foregroundStyle(MantisTheme.pink)
            Text(library.path).font(.callout.monospaced()).textSelection(.enabled)
            HStack {
                Button("Elegir otra carpeta…", action: chooseLibrary)
                if library.standardizedFileURL.path != LibraryPreferences.suggestedRoot().standardizedFileURL.path {
                    Button("Elegir ~/Mantis") { library = LibraryPreferences.suggestedRoot(); error = nil }
                }
            }.disabled(model.busy || navigation.advancing)
            if let current = model.store?.root, !libraryApplied {
                DisclosureGroup("O conservar la ubicación anterior") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(current.path).font(.caption).textSelection(.enabled)
                        Button("Mantener esta ubicación") { library = current; error = nil }
                    }.padding(.top, 6)
                }.font(.caption).disabled(model.busy || navigation.advancing)
            }
            if !libraryApplied {
                Text("Pulsa «Usar carpeta y continuar» para guardar esta elección y pasar al siguiente paso. Si tienes grabaciones anteriores, se copiarán aquí; los originales se conservan y no se sobrescriben reuniones existentes. La copia puede necesitar espacio adicional.")
                    .font(.caption).foregroundStyle(MantisTheme.secondary)
            } else {
                Label("Ubicación configurada", systemImage: "checkmark.circle.fill").foregroundStyle(MantisTheme.green)
            }
            Text("Los modelos grandes se guardan aparte. Si eliges iCloud, Dropbox u otra carpeta sincronizada, ese servicio puede subir sus archivos; para mantenerlos en este Mac, usa una carpeta local.")
                .font(.caption).foregroundStyle(MantisTheme.secondary)
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dale acceso a tu audio").font(.title2.bold())
            CapturePermissionsView(model: model)
            Text("Puedes continuar y autorizarlos después desde Ajustes → Privacidad.")
                .font(.caption).foregroundStyle(MantisTheme.secondary)
        }
    }

    private var transcriptionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Un modelo para tus palabras").font(.title2.bold())
            Text("Descarga uno del catálogo o usa el que ya tienes. Una vez instalado, transcribe sin conexión.")
                .foregroundStyle(MantisTheme.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(transcriptionChoice.modelFileName == nil ? "Solo guardar audio" : "Modelo elegido")
                        .font(.caption).foregroundStyle(MantisTheme.secondary)
                    Text(transcriptionChoice.modelFileName.flatMap { id in
                        model.localModels.first(where: { $0.id == id })?.name
                    } ?? "Puedes elegirlo más adelante").font(.callout.weight(.medium))
                }
                Spacer()
                Button("Elegir después") { transcriptionChoice.modelFileName = nil }.disabled(model.busy)
            }.padding(12).background(MantisTheme.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            ModelBrowserView(model: model, selection: $transcriptionChoice.modelFileName)
            if transcriptionChoice.modelFileName != nil {
                Text("Al pulsar «Usar modelo y abrir Mantis» confirmarás esta elección. Los modelos existentes no se borran.")
                    .font(.caption).foregroundStyle(MantisTheme.secondary)
                Toggle("Transcribir automáticamente al detener", isOn: $transcriptionChoice.automaticTranscription)
                    .disabled(model.busy)
                Text("Apagado por defecto: guarda solo audio y permite transcribir después con el modelo elegido.")
                    .font(.caption).foregroundStyle(MantisTheme.secondary)
            } else {
                Text("Guardarás solo audio. No se borra ningún modelo que ya tengas; podrás elegirlo después desde Ajustes.")
                    .font(.caption)
            }
            Divider()
            Label("Grabaciones con nombre automático de fecha y hora, editable después.", systemImage: "calendar")
            Label("Procesamiento local. No enviamos grabaciones ni textos a un servidor.", systemImage: "lock.shield")
            Text("Carpeta: \(model.store?.root.path ?? "No disponible")").font(.caption.monospaced()).textSelection(.enabled)
        }
    }

    private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Elegir carpeta de grabaciones de Mantis"
        panel.prompt = "Elegir carpeta"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = library
        if panel.runModal() == .OK, let url = panel.url { library = url; error = nil }
    }
}

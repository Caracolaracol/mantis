import AppKit
import MeetingCore
import SwiftUI

enum MantisSettingsPage: String, CaseIterable, Identifiable {
    case general = "General", recording = "Grabación", models = "Modelos", files = "Archivos", privacy = "Privacidad"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .recording: return "waveform"
        case .models: return "square.stack.3d.up"
        case .files: return "folder"
        case .privacy: return "lock.shield"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    private var page: MantisSettingsPage { model.settingsPage }
    @State private var pendingTextFolder: URL?
    @State private var pendingLibrary: URL?
    @State private var storageError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ajustes de Mantis").font(.title2.bold()).foregroundStyle(MantisTheme.pink)
                    Text("Tu grabación, a tu manera.").font(.callout).foregroundStyle(MantisTheme.secondary)
                }
                Spacer()
                Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(MantisTheme.green)
            }
            HStack(spacing: 8) {
                ForEach(MantisSettingsPage.allCases) { item in
                    Button { model.settingsPage = item } label: { Label(item.rawValue, systemImage: item.symbol).frame(maxWidth: .infinity) }
                        .buttonStyle(MantisFilterStyle(selected: page == item))
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch page {
                    case .general: GeneralSettingsView()
                    case .recording: RecordingSettingsView(model: model)
                    case .models: modelSettings
                    case .files: fileSettings
                    case .privacy: privacySettings
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 6)
            }
            HStack {
                Image(systemName: "checkmark.circle").foregroundStyle(MantisTheme.green)
                Text("Los ajustes se guardan automáticamente.").font(.caption).foregroundStyle(MantisTheme.secondary)
                Spacer()
                Text("Mantis · local").font(.caption2).foregroundStyle(MantisTheme.secondary)
            }
        }.padding(24).frame(width: 810, height: 700).mantisAppearance()
            .onAppear { model.refreshAudioInputs(); model.refreshPermissions() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { model.refreshPermissions() } }
            .alert("¿Cambiar carpeta de textos?", isPresented: Binding(get: { pendingTextFolder != nil }, set: { if !$0 { pendingTextFolder = nil } }), presenting: pendingTextFolder) { folder in
                Button("Cancelar", role: .cancel) { pendingTextFolder = nil }
                Button("Usar carpeta y copiar textos") {
                    pendingTextFolder = nil
                    Task { do { try await model.useTextFolder(at: folder) } catch { storageError = error.localizedDescription } }
                }
            } message: { folder in
                Text("TXT nuevos en \(folder.path). Se copiarán los textos existentes conservando originales; no se sobrescriben contenidos diferentes. Los audios no se mueven.")
            }
            .alert("¿Cambiar carpeta de audios?", isPresented: Binding(get: { pendingLibrary != nil }, set: { if !$0 { pendingLibrary = nil } }), presenting: pendingLibrary) { folder in
                Button("Cancelar", role: .cancel) { pendingLibrary = nil }
                Button("Copiar y usar carpeta") {
                    pendingLibrary = nil
                    Task { do { try await model.useLibrary(at: folder, keepingTextFolder: true) } catch { storageError = error.localizedDescription } }
                }
            } message: { folder in
                Text("Se copiarán los audios y el historial interno a \(folder.path). La ubicación de los textos no cambia. Los originales se conservan; puede requerir espacio adicional.")
            }
    }

    private var modelSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Transcribir automáticamente al detener", isOn: $model.automaticTranscription).disabled(model.busy)
                Text("Apagado por defecto. También puedes elegir un modelo y transcribir solo cuando lo necesites.")
                    .font(.caption).foregroundStyle(MantisTheme.secondary)
            }.mantisCard()
            ModelBrowserView(model: model, selection: Binding(get: { Optional(model.selectedModelFileName) }, set: { if let id = $0 { model.selectModel(id) } }))
                .mantisCard()
        }
    }

    private var fileSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Ubicación de los archivos", systemImage: "folder.fill").font(.headline).foregroundStyle(MantisTheme.pink)
                Text("Por defecto, los textos TXT y los audios M4A se guardan en la misma carpeta. Puedes cambiar cada ubicación por separado. Los archivos comparten nombre de fecha y hora, sin subcarpetas por reunión.")
                    .font(.callout).foregroundStyle(MantisTheme.secondary)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Label("Ubicación de los textos", systemImage: "doc.text").font(.headline)
                    Text(model.store?.textRoot.path ?? "No disponible").font(.callout.monospaced()).textSelection(.enabled)
                    Button("Cambiar carpeta") { chooseFolder(forText: true) }.disabled(model.busy || model.store == nil)
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Label("Ubicación de los audios", systemImage: "waveform").font(.headline)
                    Text(model.store?.root.path ?? "No disponible").font(.callout.monospaced()).textSelection(.enabled)
                    Button("Cambiar carpeta") { chooseFolder(forText: false) }.disabled(model.busy || model.store == nil)
                }
                Text("Al cambiar una carpeta, se copian los archivos correspondientes y se conservan los originales. El historial interno puede contener texto aunque los TXT estén en otra carpeta; separarlos no es un límite de privacidad.")
                    .font(.caption).foregroundStyle(MantisTheme.secondary)
            }.mantisCard()
            Text("Si eliges iCloud o una carpeta sincronizada, ese proveedor puede subir sus archivos. Usa una carpeta local para mantenerlos solo en este Mac.")
                .font(.caption).foregroundStyle(MantisTheme.secondary)
            if let storageError { Text(storageError).font(.caption).foregroundStyle(MantisTheme.pink) }
        }
    }

    private var privacySettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            CapturePermissionsView(model: model)
            PermissionResetView(model: model)
            VStack(alignment: .leading, spacing: 12) {
                Label("Privado por diseño", systemImage: "lock.shield").font(.headline).foregroundStyle(MantisTheme.pink)
                Text("Solo audio, nunca imágenes ni video. Inferencia local con transcribe.cpp \(NativeTranscriber.version); no enviamos tus grabaciones ni textos.")
                    .font(.callout).foregroundStyle(MantisTheme.secondary)
                Text("Los modelos se descargan de Hugging Face solo cuando lo confirmas. No hay cifrado adicional al disco: considera FileVault para proteger archivos locales.")
                    .font(.caption).foregroundStyle(MantisTheme.secondary)
                Divider()
                Button("Repetir bienvenida inicial…") { openWindow(id: "main"); model.showingOnboarding = true }.disabled(model.busy)
                Text("Esto sí abre el onboarding. Los ajustes normales de esta ventana no lo necesitan.")
                    .font(.caption).foregroundStyle(MantisTheme.secondary)
            }.mantisCard()
        }
    }

    private func chooseFolder(forText: Bool) {
        storageError = nil
        let panel = NSOpenPanel()
        panel.title = forText ? "Ubicación de los textos" : "Ubicación de los audios"
        panel.directoryURL = forText ? model.store?.textRoot : model.store?.root
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let folder = panel.url {
            if forText { pendingTextFolder = folder } else { pendingLibrary = folder }
        }
    }
}

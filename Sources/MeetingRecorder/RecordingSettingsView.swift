import MeetingCore
import SwiftUI

struct RecordingSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Fuentes de audio", systemImage: "waveform").font(.headline).foregroundStyle(MantisTheme.pink)
                Picker("Qué grabar", selection: $model.mode) {
                    ForEach(RecordingMode.allCases) { Text($0.title).tag($0) }
                }.disabled(model.busy || model.loadingApplications)
                Text(model.mode.explanation).font(.callout).foregroundStyle(MantisTheme.secondary)
                if model.mode.capturesApplication {
                    HStack {
                        Picker("Aplicación", selection: $model.selectedApplicationID) {
                            Text("Seleccionar aplicación…").tag(Int32?.none)
                            ForEach(model.applications, id: \.processID) { Text($0.applicationName).tag(Optional($0.processID)) }
                        }
                        Button(model.loadingApplications ? "Cargando…" : "Actualizar", action: model.loadApplications)
                    }.disabled(model.busy || model.loadingApplications)
                }
            }.mantisCard()
            if model.mode.capturesMicrophone {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Tu voz / interfaz", systemImage: "mic").font(.headline).foregroundStyle(MantisTheme.pink)
                    AudioInputPicker(model: model)
                }.mantisCard()
            }
            HStack(spacing: 12) {
                Image(systemName: "music.note").font(.title2).foregroundStyle(MantisTheme.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("M4A · solo audio").font(.headline)
                    Text("AAC compacto, sin video. Nombre automático con fecha y hora, editable después.")
                        .font(.caption).foregroundStyle(MantisTheme.secondary)
                }
            }.mantisCard()
        }
    }
}

struct CapturePermissionsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Acceso a las fuentes elegidas").font(.headline)
            Text("macOS autoriza por separado tu entrada y el sonido de las aplicaciones. Conceder un permiso no inicia una grabación.")
                .font(.callout).foregroundStyle(MantisTheme.secondary)
            ForEach(model.permissionSnapshot.required(for: model.mode)) { kind in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(kind.title, systemImage: model.permissionSnapshot[kind] == .allowed ? "checkmark.circle.fill" : "questionmark.circle")
                        Text(model.permissionSnapshot[kind].title).font(.caption).foregroundStyle(MantisTheme.secondary)
                    }
                    Spacer()
                    Button("Abrir Ajustes de macOS") { model.openPermissionSettings(kind) }.disabled(model.busy)
                }.padding(.vertical, 5)
            }
            HStack {
                Button(AppLocalization.text(model.configuringPermissions ? "Solicitando…" : "Solicitar accesos")) {
                    Task { await model.requestConfiguredPermissions() }
                }.disabled(model.busy)
                Button("Actualizar estado", action: model.refreshPermissions).disabled(model.busy)
            }
            if let message = model.permissionSetupMessage {
                Text(AppLocalization.message(message)).font(.caption).foregroundStyle(MantisTheme.pink).textSelection(.enabled)
            }
            Text("El audio del computador usa el permiso Grabación de pantalla y audio del sistema. Mantis nunca guarda imágenes ni video. Si macOS solicita reiniciar la app, sal desde el menú y vuelve a abrirla.")
                .font(.caption).foregroundStyle(MantisTheme.secondary)
        }.mantisCard()
    }
}

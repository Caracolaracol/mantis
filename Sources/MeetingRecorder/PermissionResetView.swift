import AppKit
import MeetingCore
import SwiftUI

struct PermissionResetView: View {
    @ObservedObject var model: AppModel
    @State private var confirmingReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recuperar permiso de audio", systemImage: "arrow.counterclockwise")
                .font(.headline).foregroundStyle(MantisTheme.pink)
            Text("Úsalo si macOS muestra a Mantis como autorizada, pero la app no puede acceder al audio del computador después de una actualización.")
                .font(.callout).foregroundStyle(MantisTheme.secondary)
            Button(AppLocalization.text(model.systemAudioPermissionResetState == .running ? "Restableciendo…" : "Restablecer permiso de audio…")) {
                confirmingReset = true
            }.disabled(model.busy || model.loadingApplications || model.systemAudioPermissionResetState == .requiresRestart)
            Text("Solo se restablece el permiso de pantalla y audio del sistema de Mantis. No se tocan el micrófono, otras apps ni tus archivos. Tendrás que salir, volver a abrir Mantis y autorizarla de nuevo.")
                .font(.caption).foregroundStyle(MantisTheme.secondary)
            switch model.systemAudioPermissionResetState {
            case .requiresRestart:
                Text(AppLocalization.text(SystemAudioPermissionReset.restartMessage)).font(.callout).foregroundStyle(MantisTheme.green)
                Button("Salir de Mantis") { NSApp.terminate(nil) }.disabled(model.busy)
            case .failed(let message):
                Text(AppLocalization.format("No se pudo restablecer el permiso: %@", AppLocalization.message(message))).font(.caption).foregroundStyle(MantisTheme.pink).textSelection(.enabled)
            case .idle, .running: EmptyView()
            }
        }.mantisCard()
        .alert("¿Restablecer el permiso de audio de Mantis?", isPresented: $confirmingReset) {
            Button("Cancelar", role: .cancel) {}
            Button("Restablecer permiso", role: .destructive) {
                Task { await model.resetSystemAudioPermission() }
            }
        } message: {
            Text("Se ejecutará: tccutil reset ScreenCapture local.agus.MeetingRecorder\n\nEsto elimina la autorización anterior de Mantis para pantalla y audio del sistema; no concede acceso nuevo. Después deberás salir, volver a abrir la app y aprobarla en macOS. No se borra ningún archivo ni se restablece el micrófono.")
        }
    }
}

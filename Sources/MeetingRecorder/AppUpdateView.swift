import MeetingCore
import SwiftUI

struct AppUpdateNotice: View {
    @ObservedObject var updates: AppUpdateController
    var isBusy: Bool

    var body: some View {
        if !isBusy {
            switch updates.state {
            case .available(let release):
                VStack(alignment: .leading, spacing: 12) {
                    Label(AppLocalization.format("Mantis %@ está disponible", release.version.description), systemImage: "arrow.down.circle")
                        .font(.headline).foregroundStyle(MantisTheme.pink)
                    Text("La descarga es manual. Sal de Mantis antes de reemplazar la app; esta versión no instala actualizaciones automáticamente.")
                        .font(.caption).foregroundStyle(MantisTheme.secondary)
                    ViewThatFits {
                        HStack { actions(release) }
                        VStack(alignment: .leading) { actions(release) }
                    }
                }.mantisCard()
            case .checking:
                HStack { ProgressView().controlSize(.small); Text("Buscando actualizaciones…") }
            case .upToDate:
                HStack {
                    Text("Mantis está actualizado.")
                    Spacer()
                    Button("Cerrar") { updates.dismiss() }
                }.font(.callout)
            case .failed:
                HStack {
                    Text("No se pudo consultar GitHub. Revisa tu conexión e inténtalo más tarde.")
                    Spacer()
                    Button("Cerrar") { updates.dismiss() }
                }.font(.callout).foregroundStyle(MantisTheme.secondary)
            case .idle: EmptyView()
            }
        }
    }

    @ViewBuilder private func actions(_ release: AppRelease) -> some View {
        Link("Ver novedades", destination: release.pageURL)
        Link("Descargar actualización…", destination: release.pageURL)
        Button("Más tarde") { updates.dismiss() }
        Button("Omitir esta versión") { updates.skip(release) }
    }
}

struct AppUpdateSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: AppUpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Actualizaciones", systemImage: "arrow.down.circle").font(.headline).foregroundStyle(MantisTheme.pink)
            Text(AppLocalization.format("Versión instalada: %@", updates.installedVersion)).font(.caption)
            Toggle("Buscar versiones nuevas automáticamente", isOn: $updates.automaticChecks)
            Text("Desactivado por defecto. Al activarlo, Mantis consulta GitHub al abrir y mientras está en reposo, como máximo una vez al día. GitHub recibe la solicitud y tu dirección IP, nunca tus audios ni textos. No se descarga ni instala nada automáticamente.")
                .font(.caption).foregroundStyle(MantisTheme.secondary)
            Button("Buscar actualizaciones…") { Task { await updates.check(isBusy: model.busy) } }
                .disabled(model.busy || updates.isChecking)
            AppUpdateNotice(updates: updates, isBusy: model.busy)
        }.mantisCard()
        .onChange(of: updates.automaticChecks) { _, enabled in
            if enabled { model.checkForUpdatesAutomatically() }
        }
    }
}

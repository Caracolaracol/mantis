import Combine
import MeetingCore
import ServiceManagement
import SwiftUI

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var error: String?
    private let readStatus: () -> SMAppService.Status
    private let changeRegistration: (Bool) throws -> Void

    var isRegistered: Bool { status == .enabled || status == .requiresApproval }

    init(readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         changeRegistration: @escaping (Bool) throws -> Void = { enabled in
             if enabled { try SMAppService.mainApp.register() }
             else { try SMAppService.mainApp.unregister() }
         }) {
        self.readStatus = readStatus
        self.changeRegistration = changeRegistration
        refresh()
    }

    func refresh() { status = readStatus() }

    func setEnabled(_ enabled: Bool) {
        error = nil
        do { try changeRegistration(enabled) }
        catch { self.error = "No se pudo cambiar el inicio automático: \(error.localizedDescription)" }
        refresh()
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(LaunchPreferences.startInMenuBarKey) private var startInMenuBar = false
    @StateObject private var login = LoginItemController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Idioma", systemImage: "globe").font(.headline).foregroundStyle(MantisTheme.pink)
                Picker("Idioma", selection: $model.language) {
                    ForEach(AppLanguage.allCases) { language in Text(verbatim: language.name).tag(language) }
                }.disabled(model.busy)
                Text("Elige el idioma de Mantis. El inglés es el idioma predeterminado.")
                    .font(.callout).foregroundStyle(MantisTheme.secondary)
            }.mantisCard()
            VStack(alignment: .leading, spacing: 12) {
                Label("Al abrir Mantis", systemImage: "menubar.rectangle").font(.headline).foregroundStyle(MantisTheme.pink)
                Toggle("Iniciar en la barra de menús, sin abrir la ventana", isOn: $startInMenuBar)
                Text("Se aplica la próxima vez que abras Mantis. Puedes abrir la biblioteca desde su icono en la barra de menús. La bienvenida inicial se muestra hasta completar la configuración.")
                    .font(.callout).foregroundStyle(MantisTheme.secondary)
            }.mantisCard()
            VStack(alignment: .leading, spacing: 12) {
                Label("Inicio de sesión", systemImage: "power").font(.headline).foregroundStyle(MantisTheme.pink)
                Toggle("Abrir Mantis al iniciar sesión en macOS", isOn: Binding(get: { login.isRegistered }, set: { login.setEnabled($0) }))
                Text("Instala Mantis en Aplicaciones antes de activar esta opción. Si también activas el inicio sin ventana, quedará directamente en la barra de menús. No inicia grabaciones.")
                    .font(.callout).foregroundStyle(MantisTheme.secondary)
                if login.status == .requiresApproval {
                    Text("macOS requiere tu aprobación en Ítems de inicio.").font(.callout).foregroundStyle(MantisTheme.pink)
                    Button("Abrir Ítems de inicio de macOS") { SMAppService.openSystemSettingsLoginItems() }
                }
                if login.status == .notFound {
                    Text("macOS no encuentra esta app como ítem de inicio. Abre la copia instalada en Aplicaciones y vuelve a intentarlo.")
                        .font(.caption).foregroundStyle(MantisTheme.pink)
                }
                if let error = login.error { Text(AppLocalization.message(error)).font(.caption).foregroundStyle(MantisTheme.pink) }
            }.mantisCard()
        }
        .onAppear { login.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { login.refresh() } }
    }
}

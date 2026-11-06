import AppKit
import MeetingCore
import SwiftUI
import UniformTypeIdentifiers

/// One model experience, shared by onboarding and the dedicated settings window.
struct ModelBrowserView: View {
    @ObservedObject var model: AppModel
    @Binding var selection: String?
    @State private var query = ""
    @State private var installedOnly = false
    @State private var pendingDownload: CatalogModel?
    @State private var importError: String?

    private var results: [CatalogModel] {
        ModelCatalog.matching(query).filter { item in
            !installedOnly || model.localModels.contains(where: { $0.id == item.fileName })
        }
    }

    private var moreModelsURL: URL {
        var parts = URLComponents(string: "https://huggingface.co/models")!
        parts.queryItems = [URLQueryItem(name: "search", value: "handy-computer/" + query)]
        return parts.url!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Modelos de transcripción", systemImage: "waveform.badge.magnifyingglass").font(.headline)
                Spacer()
                Button("Importar local…", systemImage: "square.and.arrow.down", action: importModel)
                    .disabled(model.busy)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(MantisTheme.secondary)
                TextField("Buscar en el catálogo: Whisper, Nemotron, español…", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }.padding(11).background(MantisTheme.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
            HStack {
                Button("Todos") { installedOnly = false }.buttonStyle(MantisFilterStyle(selected: !installedOnly))
                Button("Descargados") { installedOnly = true }.buttonStyle(MantisFilterStyle(selected: installedOnly))
                Spacer()
                Link("Más en Internet ↗", destination: moreModelsURL).font(.caption)
                Text("\(results.count) en catálogo").font(.caption).foregroundStyle(MantisTheme.secondary)
            }
            if let local = model.localModels.first(where: { $0.id == "default.gguf" }),
               query.isEmpty || local.name.localizedStandardContains(query) || AppLocalization.text(local.name).localizedStandardContains(query) {
                HStack(spacing: 12) {
                    modelIcon("internaldrive", color: MantisTheme.pink)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tu modelo local").font(.headline)
                        Text("Importado · default.gguf").font(.caption).foregroundStyle(MantisTheme.secondary)
                    }
                    Spacer()
                    useButton(local.id)
                }.padding(14).background(MantisTheme.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            }
            ForEach(results) { item in modelCard(item) }
            if results.isEmpty {
                Text("No hay modelos para este filtro. Prueba otro nombre o revisa Hugging Face.")
                    .font(.callout).foregroundStyle(MantisTheme.secondary).padding(.vertical, 12)
            }
            if let error = importError ?? model.modelDownloadError {
                Label(AppLocalization.message(error), systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(MantisTheme.pink)
            }
            HStack {
                Label("Inferencia local · descargas de Hugging Face", systemImage: "lock.shield").font(.caption2)
            }.foregroundStyle(MantisTheme.secondary)
            Text("Catálogo curado compatible con el motor integrado. Descargas solo con tu confirmación; nunca se envían audios ni textos. Otros GGUF pueden importarse si son compatibles.")
                .font(.caption2).foregroundStyle(MantisTheme.secondary)
        }
        .alert("¿Descargar \(pendingDownload?.name ?? "modelo")?", isPresented: Binding(get: { pendingDownload != nil }, set: { if !$0 { pendingDownload = nil } }), presenting: pendingDownload) { item in
            Button("Cancelar", role: .cancel) { pendingDownload = nil }
            Button("Descargar") { model.downloadModel(item); pendingDownload = nil }
        } message: { item in
            Text("\(AppLocalization.byteCount(item.byteCount)) desde \(item.repositoryURL.absoluteString).\nLicencia: \(item.license). Se verificará SHA-256. Puede requerir temporalmente el doble de espacio. Después podrás pulsar Usar para elegirlo.")
        }
    }

    private func modelCard(_ item: CatalogModel) -> some View {
        let installed = model.localModels.contains(where: { $0.id == item.fileName })
        let downloading = model.modelDownloadID == item.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                modelIcon(item.id.contains("whisper") ? "waveform" : "brain", color: MantisTheme.green)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name).font(.headline)
                    Text(AppLocalization.text(item.details)).font(.caption).foregroundStyle(MantisTheme.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        badge(AppLocalization.text("Español"))
                        badge(AppLocalization.byteCount(item.byteCount))
                        if installed { badge("Local", color: MantisTheme.green) }
                    }
                }
                Spacer(minLength: 4)
                if installed { useButton(item.fileName) }
                else if !downloading {
                    Button { pendingDownload = item } label: { Label("Descargar", systemImage: "arrow.down") }
                        .buttonStyle(.bordered).disabled(model.busy || model.models == nil)
                }
            }
            if downloading {
                HStack(spacing: 10) {
                    ProgressView(value: model.modelDownloadProgress)
                    Text(model.modelDownloadProgress >= 1 ? AppLocalization.text("Verificando…") : "\(Int(model.modelDownloadProgress * 100)) %")
                        .font(.caption.monospacedDigit())
                    Button("Cancelar", action: model.cancelModelDownload)
                }
            }
            HStack {
                Text(AppLocalization.text(item.license)).font(.caption2).foregroundStyle(MantisTheme.secondary)
                Spacer()
                Link("Ficha del modelo ↗", destination: item.repositoryURL).font(.caption2)
            }
        }.padding(14)
            .background(MantisTheme.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selection == item.fileName ? MantisTheme.green : MantisTheme.border.opacity(0.7), lineWidth: 1))
    }

    private func useButton(_ id: String) -> some View {
        Button(AppLocalization.text(selection == id ? "Elegido ✓" : "Usar")) { selection = id }
            .buttonStyle(.bordered).tint(selection == id ? MantisTheme.green : MantisTheme.pink)
            .disabled(model.busy || selection == id)
    }

    private func badge(_ text: String, color: Color = MantisTheme.secondary) -> some View {
        Text(text).font(.caption2.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.08), in: Capsule())
    }

    private func modelIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name).font(.title3).foregroundStyle(color)
            .frame(width: 38, height: 38).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private func importModel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gguf") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            importError = nil
            model.importModel(url, onSuccess: { selection = model.selectedModelFileName }, onFailure: { importError = $0 })
        }
    }
}

struct MantisFilterStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.caption.weight(.semibold))
            .foregroundStyle(selected ? MantisTheme.background : MantisTheme.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(selected ? MantisTheme.green : MantisTheme.background.opacity(0.45), in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

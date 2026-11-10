import AppKit
import MeetingCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var search = ""
    @State private var confirmDeletion = false
    @State private var meetingToRename: Meeting?
    @State private var editedTitle = ""
    @State private var renameError: String?
    @Environment(\.scenePhase) private var scenePhase

    private var visibleMeetings: [Meeting] {
        search.isEmpty ? model.meetings : model.meetings.filter { $0.title.localizedStandardContains(search) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                AppUpdateNotice(updates: model.updates, isBusy: model.busy)
                recordingCard.mantisCard()
                if model.modelDownloadID != nil {
                    HStack {
                        ProgressView(value: model.modelDownloadProgress)
                        Text("Descargando modelo…").font(.caption)
                        Button("Cancelar", action: model.cancelModelDownload)
                    }.mantisCard()
                }
                library.mantisCard()
                if let meeting = model.selectedMeeting { detail(meeting).mantisCard() }
                storageFooter
            }.frame(maxWidth: 900).padding(24).frame(maxWidth: .infinity)
        }
        .frame(minWidth: 700, minHeight: 680).mantisAppearance()
        .onAppear { model.refreshPermissions() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refreshPermissions() } }
        .alert("Mantis", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("Aceptar") { model.alert = nil }
        } message: { Text(AppLocalization.message(model.alert ?? "")) }
        .alert("¿Eliminar esta grabación?", isPresented: $confirmDeletion) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar audio y texto", role: .destructive) { model.deleteSelected() }
        } message: { Text("Se eliminarán el audio, el texto y su registro local. No se puede deshacer.") }
        .sheet(item: $meetingToRename) { meeting in
            VStack(alignment: .leading, spacing: 16) {
                Text("Renombrar grabación").font(.title3.bold()).foregroundStyle(MantisTheme.pink)
                TextField("Nombre", text: $editedTitle).textFieldStyle(.roundedBorder)
                if let renameError { Text(AppLocalization.message(renameError)).font(.caption).foregroundStyle(MantisTheme.pink) }
                HStack {
                    Spacer()
                    Button("Cancelar") { meetingToRename = nil }.keyboardShortcut(.cancelAction)
                    Button("Guardar") {
                        do { try model.renameMeeting(meeting.id, to: editedTitle); meetingToRename = nil }
                        catch { renameError = error.localizedDescription }
                    }.keyboardShortcut(.defaultAction)
                        .disabled(model.busy || editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 420).mantisAppearance()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            MantisBrandMark(size: 32)
                .frame(width: 48, height: 48).background(MantisTheme.pink.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text("Mantis").font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(MantisTheme.pink)
            }
            Spacer()
            SettingsLink { Label("Ajustes", systemImage: "gearshape") }
                .buttonStyle(.bordered).help("Ajustes generales de Mantis · ⌘,")
        }
    }

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.text(model.activeMeetingID != nil ? "GRABANDO" : "TU AUDIO, EN ESTE MAC"))
                        .font(.caption2.weight(.bold)).tracking(1.5)
                        .foregroundStyle(model.activeMeetingID != nil ? Color.red : MantisTheme.green)
                    if model.activeMeetingID != nil {
                        Text(clock(model.elapsed)).font(.system(size: 32, weight: .medium, design: .monospaced))
                    } else {
                        Text(model.mode.title).font(.title3.weight(.semibold))
                    }
                    Text(AppLocalization.text(model.automaticTranscription ? "Guardar audio y transcribir al detener" : "Guardar audio · transcribir cuando tú quieras"))
                        .font(.caption).foregroundStyle(MantisTheme.secondary)
                }
                Spacer()
                if model.activeMeetingID != nil {
                    Button("Detener y guardar", systemImage: "stop.fill") { model.stopRecording() }
                        .buttonStyle(.borderedProminent).tint(.red).disabled(model.preparing)
                } else if model.busy {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(AppLocalization.message(model.phase.isEmpty ? "Preparando…" : model.phase)).font(.caption)
                        if model.startingRecording {
                            Button("Cancelar preparación", action: model.cancelRecordingPreparation)
                                .font(.caption)
                        }
                    }.frame(maxWidth: 190)
                } else {
                    Button("Grabar audio", systemImage: "record.circle.fill", action: model.startRecording)
                        .buttonStyle(.borderedProminent).controlSize(.large).foregroundStyle(MantisTheme.background)
                        .disabled(model.loadingApplications || model.store == nil)
                }
            }
            Divider().overlay(MantisTheme.border.opacity(0.5))
            HStack(spacing: 12) {
                Label("Solo audio · M4A", systemImage: "music.note").font(.caption).foregroundStyle(MantisTheme.green)
                Label("Local", systemImage: "lock.shield").font(.caption).foregroundStyle(MantisTheme.secondary)
                Spacer()
            }
        }.padding(4)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tu biblioteca").font(.headline)
                Text("\(model.meetings.count)").font(.caption).foregroundStyle(MantisTheme.green)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(MantisTheme.green.opacity(0.1), in: Capsule())
                Spacer()
                Button("Abrir en Finder", systemImage: "folder", action: model.openLibraryFolder)
                    .help("Abrir la carpeta de audios de la biblioteca")
                    .disabled(model.store == nil)
                Button("Importar audio", systemImage: "plus", action: importAudio)
                    .disabled(model.busy || model.loadingApplications || model.store == nil)
            }
            if !model.meetings.isEmpty {
                Text("Arrastra un audio a otra aplicación para usar su archivo.")
                    .font(.caption).foregroundStyle(MantisTheme.secondary)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(MantisTheme.secondary)
                    TextField("Buscar grabaciones…", text: $search).textFieldStyle(.plain)
                }.padding(9).background(MantisTheme.background.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
            if visibleMeetings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform").font(.largeTitle).foregroundStyle(MantisTheme.green.opacity(0.7))
                    Text(AppLocalization.text(search.isEmpty ? "Tu biblioteca está lista" : "Sin resultados")).font(.headline)
                    Text(AppLocalization.text(search.isEmpty ? "Las grabaciones guardadas aparecerán aquí." : "Prueba con otro nombre."))
                        .font(.caption).foregroundStyle(MantisTheme.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 25)
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(visibleMeetings) { meeting in
                            Button { model.selection = meeting.id } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: meeting.status == .failed ? "exclamationmark.circle" : "waveform")
                                        .foregroundStyle(meeting.status == .failed ? MantisTheme.pink : MantisTheme.green)
                                        .frame(width: 30, height: 34)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(meeting.title).font(.callout.weight(.semibold)).lineLimit(1)
                                        Text(meeting.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(model.language.locale)))
                                            .font(.caption2).foregroundStyle(MantisTheme.secondary)
                                    }
                                    Spacer()
                                    Text(meeting.status.title).font(.caption2).foregroundStyle(MantisTheme.secondary)
                                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(MantisTheme.secondary)
                                }.padding(10).contentShape(Rectangle())
                                    .background(model.selection == meeting.id ? MantisTheme.green.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).accessibilityValue(model.selection == meeting.id ? AppLocalization.text("Seleccionada") : meeting.status.title)
                                .modifier(AudioFileDragModifier(url: model.activeMeetingID == meeting.id ? nil : try? model.store?.audioURL(for: meeting)) {
                                    model.selection = meeting.id
                                })
                        }
                    }
                }.frame(height: min(190, CGFloat(visibleMeetings.count) * 63))
            }
        }
    }

    private func detail(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GRABACIÓN SELECCIONADA").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(MantisTheme.green)
                    HStack {
                        Text(meeting.title).font(.title3.weight(.semibold)).textSelection(.enabled)
                        Button {
                            editedTitle = meeting.title; renameError = nil; meetingToRename = meeting
                        } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless).help("Renombrar").disabled(model.busy)
                    }
                    Text("\(clock(meeting.duration)) · \(meeting.status.title)")
                        .font(.caption).foregroundStyle(MantisTheme.secondary)
                }
                Spacer()
                Menu {
                    Button("Mostrar este audio en Finder") { model.reveal(meeting) }
                    Button("Mostrar este TXT en Finder") { model.revealTranscript(meeting) }.disabled(meeting.transcript == nil)
                    Divider()
                    Button("Eliminar grabación…", role: .destructive) { confirmDeletion = true }.disabled(model.busy)
                } label: { Image(systemName: "ellipsis").padding(5) }.menuStyle(.borderlessButton).fixedSize()
            }
            HStack {
                Button("Reproducir audio", systemImage: "play.fill") { model.openAudio(meeting) }.disabled(model.busy)
                Spacer()
                Button(AppLocalization.text(meeting.transcript == nil ? "Transcribir" : "Volver a transcribir"), systemImage: "text.alignleft") { model.transcribe(meeting.id) }
                    .disabled(model.busy || model.loadingApplications)
            }
            if model.processingID == meeting.id {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(AppLocalization.message(model.phase)).font(.caption)
                    Spacer()
                    Button("Cancelar", action: model.cancelTranscription)
                }
            }
            if let error = meeting.error {
                DisclosureGroup("Aviso de esta grabación") { Text(AppLocalization.message(error)).font(.caption).foregroundStyle(MantisTheme.pink).textSelection(.enabled).padding(.top, 6) }
                    .font(.caption).foregroundStyle(MantisTheme.pink)
            }
            Divider()
            if let transcript = meeting.transcript {
                ScrollView {
                    Text(transcript.isEmpty ? AppLocalization.text("No se detectó voz en el audio.") : transcript)
                        .font(.body).lineSpacing(6).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 210)
                HStack {
                    Label("Transcripción local", systemImage: "lock.shield").font(.caption2).foregroundStyle(MantisTheme.secondary)
                    Spacer()
                    Button("Copiar", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(transcript, forType: .string)
                    }.font(.caption).fixedSize()
                    Menu("Exportar") {
                        Button("Texto (.txt)") { export(meeting, markdown: false) }
                        Button("Markdown (.md)") { export(meeting, markdown: true) }
                    }.font(.caption).fixedSize()
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "text.alignleft").font(.title2).foregroundStyle(MantisTheme.green)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("El audio y el texto son independientes").font(.callout.weight(.medium))
                        Text("Puedes escuchar esta grabación o transcribirla cuando quieras.").font(.caption).foregroundStyle(MantisTheme.secondary)
                    }
                }.padding(.vertical, 12)
            }
        }
    }

    private var storageFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder").foregroundStyle(MantisTheme.green)
            Text("Archivos en").font(.caption).foregroundStyle(MantisTheme.secondary)
            Text(model.store.map { ($0.root.path as NSString).abbreviatingWithTildeInPath } ?? "~/Mantis")
                .font(.caption).foregroundStyle(MantisTheme.pink).textSelection(.enabled)
            Spacer()
            Text("Audio + TXT juntos por defecto").font(.caption2).foregroundStyle(MantisTheme.secondary)
        }.padding(.horizontal, 3)
    }

    private func importAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { model.importAudio(url) }
    }

    private func export(_ meeting: Meeting, markdown: Bool) {
        guard let text = meeting.transcript else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = markdown ? [UTType(filenameExtension: "md") ?? .plainText] : [.plainText]
        panel.nameFieldStringValue = "\(meeting.title).\(markdown ? "md" : "txt")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = markdown ? "# \(meeting.title)\n\n\(meeting.createdAt.formatted())\n\n\(text)\n" : text
        do { try content.write(to: url, atomically: true, encoding: .utf8) }
        catch { model.alert = error.localizedDescription }
    }

    private func clock(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}

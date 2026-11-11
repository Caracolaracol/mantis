import AppKit
import Combine
import MeetingCore
import SwiftUI

/// Independent of the library scene: quick recordings can finish without opening it.
@MainActor
final class RecordingNameWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var observation: AnyCancellable?
    private(set) var window: NSPanel?

    init(model: AppModel) {
        self.model = model
        super.init()
        observation = model.$pendingRecordingName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in self?.present(request) }
    }

    private func present(_ request: RecordingNameRequest?) {
        guard let request else {
            let previous = window
            window = nil
            previous?.delegate = nil
            previous?.close()
            return
        }
        guard window == nil else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 270),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = AppLocalization.text("Grabación guardada")
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = NSColor(srgbRed: 18 / 255, green: 35 / 255, blue: 29 / 255, alpha: 1)
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView:
            RecordingNameView(request: request, save: { [weak model] name in
                try model?.saveRecordingName(request.id, fileStem: name)
            }, keep: { [weak model] in model?.keepRecordingName(request.id) })
                .environment(\.locale, model.language.locale))
        window = panel
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let request = model.pendingRecordingName { model.keepRecordingName(request.id) }
        return true
    }
}

struct RecordingNameView: View {
    let request: RecordingNameRequest
    let save: (String) throws -> Void
    let keep: () -> Void
    @State private var fileStem: String
    @State private var error: String?
    @FocusState private var focused: Bool

    init(request: RecordingNameRequest, save: @escaping (String) throws -> Void, keep: @escaping () -> Void) {
        self.request = request
        self.save = save
        self.keep = keep
        _fileStem = State(initialValue: request.fileStem)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                MantisBrandMark(size: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Grabación guardada").font(.title3.weight(.semibold))
                    Text("Tu audio ya está guardado. Puedes cambiar su nombre.")
                        .font(.callout).foregroundStyle(MantisTheme.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Nombre del archivo").font(.callout.weight(.medium))
                HStack {
                    TextField("Nombre del archivo", text: $fileStem)
                        .textFieldStyle(.roundedBorder).focused($focused)
                        .onSubmit(commit)
                    Text(verbatim: "." + request.fileExtension).foregroundStyle(MantisTheme.secondary)
                }
                if let error {
                    Text(AppLocalization.message(error)).font(.caption).foregroundStyle(MantisTheme.pink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button("Mantener nombre", action: keep).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Guardar nombre", action: commit).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(fileStem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 460)
        .frame(minHeight: 270, maxHeight: .infinity)
        .mantisAppearance()
        .onAppear { focused = true }
    }

    private func commit() {
        do { try save(fileStem) }
        catch { self.error = error.localizedDescription }
    }
}

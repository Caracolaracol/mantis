import AppKit
import Combine
import MeetingCore

@MainActor
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: AppModel
    private let showWindow: () -> Void
    private var observation: AnyCancellable?

    init(model: AppModel, showWindow: @escaping () -> Void) {
        self.model = model
        self.showWindow = showWindow
        super.init()
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        observation = model.objectWillChange
            .debounce(for: .milliseconds(40), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    func refresh() {
        guard let button = item.button else { return }
        let state = model.recorderStatus.state
        let symbol: String
        switch state {
        case .recording:
            symbol = "stop.circle.fill"
            let seconds = Int(model.elapsed)
            button.title = String(format: " REC %02d:%02d", seconds / 60, seconds % 60)
            button.contentTintColor = .systemRed
            button.toolTip = AppLocalization.text(model.automaticTranscription
                ? "Grabando audio. Clic: detener y transcribir. Clic derecho: opciones."
                : "Grabando audio. Clic: detener y guardar. Clic derecho: opciones.")
        case .transcribing, .preparing:
            symbol = "waveform"
            button.title = " " + AppLocalization.text(state == .transcribing ? "Transcribiendo" : "Preparando")
            button.contentTintColor = .systemOrange
            button.toolTip = AppLocalization.text("Procesamiento local en curso. Clic para abrir Mantis.")
        case .error:
            symbol = "exclamationmark.circle"
            button.title = " Mantis"
            button.contentTintColor = .systemOrange
            button.toolTip = AppLocalization.text("Hay un error. Clic para revisar.")
        case .idle:
            symbol = "record.circle"
            button.title = ""
            button.contentTintColor = nil
            button.toolTip = AppLocalization.text("Grabar todo: audio del computador + entrada seleccionada (micrófono o interfaz). Avisa a los participantes. Clic derecho: opciones.")
        }
        if state == .idle,
           let url = Bundle.main.url(forResource: "MantisTemplate", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            image.accessibilityDescription = "Mantis"
            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: button.toolTip)
        }
        button.imagePosition = .imageLeading
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        if (model.busy && model.activeMeetingID == nil) || model.alert != nil || model.showingOnboarding { showWindow() }
        else { model.toggleQuickRecording() }
    }

    private func showMenu() {
        let menu = NSMenu()
        let stopTitle = model.automaticTranscription ? "Detener y transcribir" : "Detener grabación"
        let action = NSMenuItem(title: AppLocalization.text(model.activeMeetingID == nil ? "Grabar todo: computador + entrada" : stopTitle),
                                action: #selector(toggle), keyEquivalent: "")
        action.target = self
        action.isEnabled = !model.preparing && model.processingID == nil && model.modelDownloadID == nil
        menu.addItem(action)
        let open = NSMenuItem(title: AppLocalization.text("Abrir Mantis"), action: #selector(openWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        if model.processingID != nil {
            let cancel = NSMenuItem(title: AppLocalization.text("Cancelar transcripción"), action: #selector(cancel), keyEquivalent: "")
            cancel.target = self
            menu.addItem(cancel)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: AppLocalization.text("Salir"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func toggle() { model.toggleQuickRecording() }
    @objc private func openWindow() { showWindow() }
    @objc private func cancel() { model.cancelTranscription() }
}

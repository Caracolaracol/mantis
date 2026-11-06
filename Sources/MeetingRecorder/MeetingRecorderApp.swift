import AppKit
import MeetingCore
import SwiftUI

/// Handle commands before starting SwiftUI. A second process only queues a command
/// for the single GUI instance; it never opens a second recorder or captures audio.
@main
struct MeetingRecorderLauncher {
    @MainActor static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--engine-version"] { print(NativeTranscriber.version); return }
        if arguments.count == 4, arguments[0] == "--render-ui-preview", arguments[2] == "--language",
           let language = AppLanguage(rawValue: arguments[3]) {
            do { try UIPreviewRenderer.render(to: URL(fileURLWithPath: arguments[1], isDirectory: true), language: language) }
            catch { fputs("Mantis preview: \(error.localizedDescription)\n", stderr) }
            return
        }
        do {
            let control = try RecorderControl()
            if arguments == ["--status"] {
                let data = (try? Data(contentsOf: control.statusURL)) ?? Data("{\"state\":\"offline\"}".utf8)
                print(String(decoding: data, as: UTF8.self))
                return
            }
            let command: RecorderCommand?
            switch arguments {
            case []: command = nil
            case ["--toggle-recording"]: command = .toggle
            case ["--stop-recording"]: command = .stop
            case ["--show"]: command = .show
            case ["--cancel-transcription"]: command = .cancel
            default:
                print("Mantis: --toggle-recording | --stop-recording | --show | --status | --engine-version | --cancel-transcription")
                return
            }
            let lock = try RecorderInstanceLock(directory: control.directory)
            if let command { try control.send(command) }
            else if !lock.isOwner { try control.send(.show) }
            guard lock.isOwner else { return }
            withExtendedLifetime(lock) { MeetingRecorderApp.main() }
        } catch {
            fputs("Mantis: \(error.localizedDescription)\n", stderr)
        }
    }
}

struct MeetingRecorderApp: App {
    @StateObject private var model = AppModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let startWithoutWindow = LaunchPreferences.startsWithoutWindow()

    var body: some Scene {
        Window("Mantis", id: "main") {
            MainWindowView(model: model, delegate: delegate)
        }
        .defaultSize(width: 780, height: 820)
        .defaultLaunchBehavior(startWithoutWindow ? .suppressed : .presented)
        .restorationBehavior(.disabled)
        .commands { MainWindowCommands() }
        Settings {
            SettingsView().environmentObject(model)
                .environment(\.locale, model.language.locale)
                .id(model.language)
        }
            .restorationBehavior(.disabled)
    }
}

private struct MainWindowCommands: Commands {
    static var title: String { AppLocalization.text("Mostrar biblioteca de Mantis") }
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button(Self.title) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }.keyboardShortcut("0", modifiers: .command)
        }
    }
}

private struct MainWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppModel
    let delegate: AppDelegate
    var body: some View {
        Group {
            if model.showingOnboarding {
                OnboardingView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentView(model: model)
            }
        }
        .mantisAppearance()
        .environment(\.locale, model.language.locale)
        .id(model.language)
        .background(WindowCloseGuard(busy: model.busy))
        .onAppear {
            delegate.reopenWindow = { openWindow(id: "main") }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var reopenWindow: (() -> Void)?
    private var statusBar: StatusBarController?
    private var timer: Timer?
    private var control: RecorderControl?
    private var lastPublish = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        statusBar = StatusBarController(model: model) { [weak self] in self?.showWindow() }
        do { control = try RecorderControl() }
        catch { model.alert = error.localizedDescription }
        let polling = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(polling, forMode: .common)
        timer = polling
        poll()
    }

    private func poll() {
        guard let control else { return }
        let model = AppModel.shared
        do {
            for command in try control.drain() {
                switch command {
                case .toggle:
                    if model.alert != nil || model.showingOnboarding { showWindow() }
                    else { model.toggleQuickRecording() }
                case .stop: model.stopRecording()
                case .show: showWindow()
                case .cancel: model.cancelTranscription()
                }
            }
            if Date().timeIntervalSince(lastPublish) >= 1 {
                try control.publish(model.recorderStatus)
                lastPublish = Date()
            }
        } catch {
            model.alert = error.localizedDescription
        }
    }

    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let reopenWindow { reopenWindow() }
        else if let menu = NSApp.mainMenu {
            // Commands exist before any scene content. Use their installed
            // openWindow action on first opening after a menu-bar-only launch.
            Self.performOpenWindowCommand(in: menu)
        }
    }

    @discardableResult
    private static func performOpenWindowCommand(in menu: NSMenu) -> Bool {
        for (index, item) in menu.items.enumerated() {
            if item.title == MainWindowCommands.title {
                menu.performActionForItem(at: index)
                return true
            }
            if let submenu = item.submenu, performOpenWindowCommand(in: submenu) { return true }
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard AppModel.shared.busy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = AppLocalization.text("Hay una operación en curso")
        alert.informativeText = AppLocalization.text("Detén la grabación o cancela la transcripción o descarga de modelo antes de salir para guardar correctamente los archivos.")
        alert.addButton(withTitle: AppLocalization.text("Volver"))
        alert.runModal()
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let control { try? FileManager.default.removeItem(at: control.statusURL) }
    }
}

struct WindowCloseGuard: NSViewRepresentable {
    let busy: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.standardWindowButton(.closeButton)?.isEnabled = !busy }
    }
}

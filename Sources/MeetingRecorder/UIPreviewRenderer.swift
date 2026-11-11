import AppKit
import MeetingCore
import SwiftUI

/// Explicit developer command. Uses fictional data, never opens a desktop window,
/// records audio, downloads models, or persists preferences.
@MainActor
enum UIPreviewRenderer {
    static func render(to directory: URL, language: AppLanguage) throws {
        let previous = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var overrides = previous
        overrides[AppLanguage.preferenceKey] = language.rawValue
        // Keep the host language English so Spanish previews also verify that
        // the explicit SwiftUI locale overrides the system language.
        overrides["AppleLanguages"] = ["en"]
        UserDefaults.standard.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel(preview: true)
        try capture(ContentView(model: model).environment(\.locale, language.locale), size: NSSize(width: 780, height: 1000), to: directory.appendingPathComponent("library-\(language.rawValue).png"))
        try capture(SettingsView().environmentObject(model).environment(\.locale, language.locale), size: NSSize(width: 810, height: 700), to: directory.appendingPathComponent("settings-\(language.rawValue).png"))
        try capture(OnboardingView(model: model, initialStep: 3).environment(\.locale, language.locale), size: NSSize(width: 760, height: 720), to: directory.appendingPathComponent("models-\(language.rawValue).png"))
        let updates = AppUpdateController.preview(release: AppRelease(tag: "v0.4.0")!)
        try capture(AppUpdateNotice(updates: updates, isBusy: false).padding(24).mantisAppearance().environment(\.locale, language.locale),
                    size: NSSize(width: 700, height: 260), to: directory.appendingPathComponent("update-\(language.rawValue).png"))
        let recording = Meeting(mode: .microphone, audioFileName: "\(Meeting.automaticFileStem(for: Date(timeIntervalSince1970: 1_799_000_000))).m4a")
        try capture(RecordingNameView(request: RecordingNameRequest(meeting: recording, transcribeAfterNaming: false), save: { _ in }, keep: {})
            .environment(\.locale, language.locale), size: NSSize(width: 460, height: 270),
                    to: directory.appendingPathComponent("recording-name-\(language.rawValue).png"))
    }

    private static func capture<V: View>(_ view: V, size: NSSize, to url: URL) throws {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw MeetingError.message("Could not render preview.") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw MeetingError.message("Could not encode preview.") }
        try data.write(to: url)
    }
}

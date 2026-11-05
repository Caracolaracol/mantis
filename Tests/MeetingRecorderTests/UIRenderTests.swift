import AppKit
import SwiftUI
import XCTest
@testable import MeetingRecorder

final class UIRenderTests: XCTestCase {
    /// Opt-in, synthetic view model. No real library, capture, downloads or desktop screenshots.
    @MainActor
    func testRenderSyntheticScreens() throws {
        guard let path = ProcessInfo.processInfo.environment["MANTIS_UI_PREVIEW_DIR"] else {
            throw XCTSkip("Set MANTIS_UI_PREVIEW_DIR for offscreen UI previews.")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel(preview: true)
        try render(ContentView(model: model), size: CGSize(width: 780, height: 1000), to: directory.appendingPathComponent("library.png"))
        try render(SettingsView().environmentObject(model), size: CGSize(width: 810, height: 700), to: directory.appendingPathComponent("settings.png"))
        model.settingsPage = .recording
        try render(SettingsView().environmentObject(model), size: CGSize(width: 810, height: 700), to: directory.appendingPathComponent("settings-recording.png"))
        model.settingsPage = .files
        try render(SettingsView().environmentObject(model), size: CGSize(width: 810, height: 700), to: directory.appendingPathComponent("settings-files.png"))
        model.settingsPage = .privacy
        try render(SettingsView().environmentObject(model), size: CGSize(width: 810, height: 700), to: directory.appendingPathComponent("settings-privacy.png"))
        try render(OnboardingView(model: model, initialStep: 3), size: CGSize(width: 760, height: 720), to: directory.appendingPathComponent("onboarding-models.png"))
    }

    @MainActor
    private func render<V: View>(_ content: V, size: CGSize, to url: URL) throws {
        // ImageRenderer omits AppKit-backed scroll views/buttons. Cache an offscreen
        // hosting view instead; this window is never ordered onto the desktop.
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: representation)
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try data.write(to: url)
        window.close()
    }
}

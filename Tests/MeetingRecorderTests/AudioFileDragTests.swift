import AppKit
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import MeetingRecorder

final class AudioFileDragTests: XCTestCase {
    func testProviderOffersAudioFileAndNativeFileURL() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AudioFileDragTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Reunión de prueba.m4a")
        let data = Data("synthetic audio file".utf8)
        try data.write(to: url)

        let provider = try XCTUnwrap(AudioFileDragProvider.make(for: url))
        XCTAssertEqual(provider.suggestedName, url.lastPathComponent)
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier))
        let loaded = expectation(description: "External receiver gets file contents")
        provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { file, error in
            XCTAssertNil(error)
            XCTAssertEqual(file.flatMap { try? Data(contentsOf: $0) }, data)
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 5)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testProviderRejectsMissingFilesDirectoriesAndWebURLs() throws {
        XCTAssertNil(AudioFileDragProvider.make(for: URL(fileURLWithPath: "/missing-\(UUID()).m4a")))
        XCTAssertNil(AudioFileDragProvider.make(for: FileManager.default.temporaryDirectory))
        XCTAssertNil(AudioFileDragProvider.make(for: try XCTUnwrap(URL(string: "https://example.com/audio.m4a"))))
    }

    @MainActor
    func testRowHitTestingReachesNativeMouseTrackingSurface() throws {
        let host = NSHostingView(rootView:
            Button("Grabación sintética") {}.frame(width: 500, height: 60)
                .modifier(AudioFileDragModifier(url: nil, onStart: {})))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 60), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 60)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(host.hitTest(NSPoint(x: 250, y: 30)) is NativeAudioFileDragView)
    }

    @MainActor
    func testNativeDraggingItemWritesActualFileURLToPasteboard() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AudioDrag-\(UUID()).m4a")
        try Data("audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let view = NativeAudioFileDragView(frame: NSRect(x: 0, y: 0, width: 500, height: 60))
        view.audioURL = url
        let item = try XCTUnwrap(view.draggingItem(at: NSPoint(x: 50, y: 20)))
        let writer = try XCTUnwrap(item.item as? NSPasteboardWriting)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.writeObjects([writer]))
        let received = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(received, [url])
        view.audioURL = nil
        XCTAssertNil(view.draggingItem(at: .zero))
    }

    @MainActor
    func testNativeTrackingRetainsClickSelectionWithoutDragging() throws {
        let view = NativeAudioFileDragView(frame: NSRect(x: 0, y: 0, width: 500, height: 60))
        var selections = 0
        view.onSelect = { selections += 1 }
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        view.mouseDown(with: down)
        XCTAssertEqual(selections, 0)
        view.mouseUp(with: up)
        XCTAssertEqual(selections, 1)
    }
}

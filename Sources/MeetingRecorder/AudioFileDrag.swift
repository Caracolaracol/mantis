import AppKit
import SwiftUI

enum AudioFileDragProvider {
    static func make(for url: URL) -> NSItemProvider? {
        guard url.isFileURL,
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              FileManager.default.isReadableFile(atPath: url.path),
              let provider = NSItemProvider(contentsOf: url) else { return nil }
        // Offer both the audio file contents and a native file URL for external apps.
        provider.registerObject(url as NSURL, visibility: .all)
        provider.suggestedName = url.lastPathComponent
        return provider
    }
}

struct AudioFileDragModifier: ViewModifier {
    let url: URL?
    let onStart: () -> Void

    func body(content: Content) -> some View {
        // A Button inside a ScrollView can consume SwiftUI's drag gesture. Capture
        // mouse tracking in AppKit and write an actual file URL, like Finder does.
        content.overlay {
            NativeAudioFileDragSource(url: url, onSelect: onStart)
        }
        .help("Haz clic para seleccionar o arrastra el archivo de audio a otra aplicación")
    }
}

private struct NativeAudioFileDragSource: NSViewRepresentable {
    let url: URL?
    let onSelect: () -> Void

    func makeNSView(context: Context) -> NativeAudioFileDragView {
        let view = NativeAudioFileDragView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: NativeAudioFileDragView, context: Context) {
        view.audioURL = url
        view.onSelect = onSelect
    }
}

final class NativeAudioFileDragView: NSView, NSDraggingSource {
    var audioURL: URL?
    var onSelect: () -> Void = {}
    private var mouseDownPoint: NSPoint?
    private var startedDragging = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        startedDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !startedDragging, let origin = mouseDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - origin.x, point.y - origin.y) >= 4,
              let item = draggingItem(at: point) else { return }
        startedDragging = true
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        onSelect()
    }

    override func mouseUp(with event: NSEvent) {
        if mouseDownPoint != nil, !startedDragging { onSelect() }
        mouseDownPoint = nil
    }

    func draggingItem(at point: NSPoint) -> NSDraggingItem? {
        guard let url = audioURL, AudioFileDragProvider.make(for: url) != nil else { return nil }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let image = NSWorkspace.shared.icon(forFile: url.path)
        item.setDraggingFrame(NSRect(x: point.x - 20, y: point.y - 20, width: 40, height: 40), contents: image)
        return item
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}

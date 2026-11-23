import AppKit
import SwiftUI

/// AppKit drag source for a shelf tile. SwiftUI's `onDrag` hands receivers a temporary copy from its
/// cache; this writes the original file URL, so Finder, Mail and editors get your actual file.
struct FileDragSource: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> SourceView { SourceView(url: url) }
    func updateNSView(_ view: SourceView, context: Context) { view.url = url }

    final class SourceView: NSView, NSDraggingSource {
        var url: URL
        private var downEvent: NSEvent?
        private static let dragThreshold: CGFloat = 3

        init(url: URL) {
            self.url = url
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .link, .generic] : []
        }

        override func mouseDown(with event: NSEvent) { downEvent = event }

        override func mouseDragged(with event: NSEvent) {
            guard let down = downEvent else { return }
            let dx = event.locationInWindow.x - down.locationInWindow.x
            let dy = event.locationInWindow.y - down.locationInWindow.y
            guard hypot(dx, dy) >= Self.dragThreshold else { return }
            downEvent = nil
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let side: CGFloat = 38
            let origin = convert(down.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(x: origin.x - side / 2, y: origin.y - side / 2, width: side, height: side), contents: icon)
            beginDraggingSession(with: [item], event: down, source: self)
        }

        override func mouseUp(with event: NSEvent) { downEvent = nil }

        // Right-click goes to SwiftUI so the tile's context menu still works.
        override func rightMouseDown(with event: NSEvent) { nextResponder?.rightMouseDown(with: event) }
        override func menu(for event: NSEvent) -> NSMenu? { superview?.menu(for: event) }
    }
}

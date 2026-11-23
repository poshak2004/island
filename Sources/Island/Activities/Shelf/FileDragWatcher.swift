import AppKit

/// Notices file drags from any app (Finder, Mail, browsers) heading for the notch. A drag is a file
/// drag when the drag pasteboard changed since the mouse went down and it holds file URLs.
@MainActor
final class FileDragWatcher {
    /// Whether a screen point is close enough to the notch to show the drop targets.
    var isNearIsland: (NSPoint) -> Bool = { _ in false }
    var onChange: ((Bool) -> Void)?
    private(set) var isActive = false

    private var monitors: [Any] = []
    private var baseline = NSPasteboard(name: .drag).changeCount
    private var isFileDrag = false
    /// The drag started in Island itself (dragging a file out of the shelf): never treat it as incoming.
    private var startedInIsland = false
    /// Give a drop on the Island time to land before treating mouse-up as "drag abandoned".
    private static let releaseDelay: TimeInterval = 0.35

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in
            let type = e.type
            MainActor.assumeIsolated { self?.handle(type, local: false) }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in
            let type = e.type
            MainActor.assumeIsolated { self?.handle(type, local: true) }
            return e
        }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        set(false)
    }

    /// A drop landed on the Island; the drag is over even if no mouse-up reaches us.
    func dropCompleted() {
        isFileDrag = false
        isActive = false
    }

    private func handle(_ type: NSEvent.EventType, local: Bool) {
        let pasteboard = NSPasteboard(name: .drag)
        switch type {
        case .leftMouseDown:
            baseline = pasteboard.changeCount
            isFileDrag = false
            startedInIsland = local
        case .leftMouseDragged:
            guard !startedInIsland else { return }
            if !isFileDrag, pasteboard.changeCount != baseline {
                isFileDrag = pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            }
            if isFileDrag { set(isNearIsland(NSEvent.mouseLocation)) }
        case .leftMouseUp:
            isFileDrag = false
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseDelay) { [weak self] in self?.set(false) }
        default:
            break
        }
    }

    private func set(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        onChange?(active)
    }
}

import AppKit
import IslandCore
import SwiftUI

/// Owns the single Island window: placement on the notch, mouse pass-through, hover detection and
/// keyboard focus for search. Features never reference this type — they go through ActivityManager.
@MainActor
final class IslandWindowController {
    let panel = IslandPanel()
    let model: IslandViewModel
    let search: SearchViewModel
    private var monitors: [Any] = []
    private(set) var isVisible = false

    init(model: IslandViewModel, search: SearchViewModel) {
        self.model = model
        self.search = search
        let host = IslandHostingView(rootView: IslandRootView(model: model, search: search).ignoresSafeArea())
        host.sizingOptions = []
        panel.contentView = host
        model.onModeChange = { [weak self] mode in self?.modeChanged(mode) }
    }

    // MARK: Visibility

    func show() {
        guard !isVisible else { return }
        isVisible = true
        reposition()
        panel.orderFrontRegardless()
        installMonitors()
        refreshMouseState()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        removeMonitors()
        panel.orderOut(nil)
    }

    // MARK: Geometry

    /// Pins the window's top-centre to the notch anchor. Window size is fixed per display so
    /// animations never fight a resizing window.
    func reposition() {
        guard let g = model.geometry else { return }
        let size = model.metrics.windowSize
        let frame = NSRect(x: (g.anchor.x - size.width / 2).rounded(), y: g.screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        refreshMouseState()
    }

    /// Global hit rect for the interactive region.
    var interactiveRect: NSRect {
        guard let g = model.geometry else { return .zero }
        let r = model.hitRect
        return NSRect(x: g.anchor.x + r.minX, y: g.anchor.y - r.maxY, width: r.width, height: r.height)
    }

    // MARK: Mouse

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMouseState() }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.handleOutsideClick() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.refreshMouseState() }
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] e in
            guard let self else { return e }
            nonisolated(unsafe) let event = e
            let consumed = MainActor.assumeIsolated { self.handleKey(event) }
            return consumed ? nil : e
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    func refreshMouseState() {
        let inside = interactiveRect.contains(NSEvent.mouseLocation)
        let passThrough = !inside && model.mode != .search
        if panel.ignoresMouseEvents != passThrough { panel.ignoresMouseEvents = passThrough }
        model.mouseInsideChanged(inside)
    }

    private func handleOutsideClick() {
        guard !interactiveRect.contains(NSEvent.mouseLocation) else { return }
        if model.mode == .expanded || model.mode == .search { model.clickOutside() }
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        guard model.mode == .search || model.mode == .expanded else { return false }
        if e.keyCode == 53 { // escape
            model.escape()
            return true
        }
        return model.mode == .search ? search.handleKey(e) : false
    }

    // MARK: Mode changes

    private func modeChanged(_ mode: IslandMode) {
        if mode == .search {
            panel.allowsKey = true
            panel.makeKeyAndOrderFront(nil)
            search.activate()
        } else {
            if panel.isKeyWindow { panel.resignKey() }
            panel.allowsKey = false
            search.deactivate()
        }
        refreshMouseState()
    }
}

import AppKit
import IslandCore

/// Reports whether the frontmost app has a full-screen window on the Island's display.
/// Event-driven only: app activation, Space changes and screen changes trigger a check (plus one
/// short settle re-check, since the window list lags the Space-switch animation). No polling.
@MainActor
final class FullScreenWatcher {
    /// Called with the new state whenever it changes.
    var onChange: ((Bool) -> Void)?
    /// The Island screen's frame in AppKit global coordinates, or nil when there is no screen.
    var screenFrame: () -> CGRect? = { nil }
    private(set) var isFullScreen = false
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var settleCheck: DispatchWorkItem?
    static let settleDelay: TimeInterval = 0.6

    func start() {
        guard tokens.isEmpty else { return }
        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.didActivateApplicationNotification)
        observe(ws, NSWorkspace.activeSpaceDidChangeNotification)
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
        evaluate()
    }

    func stop() {
        tokens.forEach { center, token in center.removeObserver(token) }
        tokens = []
        settleCheck?.cancel()
        settleCheck = nil
        update(false)
    }

    /// Re-checks now (e.g. after the Island moved to another display).
    func evaluate() {
        update(Self.detect(screenFrame: screenFrame()))
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }
        }
        tokens.append((center, token))
    }

    private func changed() {
        evaluate()
        settleCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        settleCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func update(_ value: Bool) {
        guard value != isFullScreen else { return }
        isFullScreen = value
        onChange?(value)
    }

    private static func detect(screenFrame: CGRect?) -> Bool {
        guard let screenFrame, let primary = NSScreen.screens.first,
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else {
            NSLog("Island: couldn't read the window list for full-screen detection")
            return false
        }
        let quartz = FullScreenDetector.quartzFrame(fromAppKit: screenFrame, primaryHeight: primary.frame.height)
        return FullScreenDetector.isFullScreen(windows: list.compactMap(WindowInfo.init), screenFrame: quartz, frontmostPID: pid)
    }
}

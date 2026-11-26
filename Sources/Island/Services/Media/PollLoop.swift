import AppKit

/// A single cancellable poll loop: runs `body`, sleeps `interval()`, repeats. Never more than one loop,
/// and `pollNow()` wakes a sleeping loop early instead of starting a second one.
@MainActor
final class PollLoop {
    private let interval: () -> TimeInterval
    private let body: () async -> Void
    private var task: Task<Void, Never>?
    private var inFlight = false

    var isRunning: Bool { task != nil }

    init(interval: @escaping () -> TimeInterval, body: @escaping () async -> Void) {
        self.interval = interval
        self.body = body
    }

    func start() {
        guard task == nil else { return }
        task = makeLoop()
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Polls right away. A poll already in flight counts; otherwise the sleeping loop is replaced by a
    /// fresh one (the old one exits as soon as its cancelled sleep returns).
    func pollNow() {
        guard task != nil, !inFlight else { return }
        task?.cancel()
        task = makeLoop()
    }

    private func makeLoop() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                // Only borrowed for the poll itself, never across the sleep.
                guard let seconds = await self?.runOnce() else { return }
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            }
        }
    }

    /// Runs one poll and returns how long to wait before the next.
    private func runOnce() async -> TimeInterval {
        inFlight = true
        await body()
        inFlight = false
        return interval()
    }
}

/// Calls back when the app with `bundleID` becomes the frontmost app (event-driven).
@MainActor
final class AppActivationObserver {
    private var token: NSObjectProtocol?

    init(bundleID: String, onActivate: @escaping () -> Void) {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == bundleID else { return }
            MainActor.assumeIsolated { onActivate() }
        }
    }

    deinit {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }

    static func isFrontmost(_ bundleID: String) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }
}

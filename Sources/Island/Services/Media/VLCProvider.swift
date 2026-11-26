import AppKit
import IslandCore

/// VLC exposes no change notifications, so this provider polls VLC's scripting dictionary — but only
/// while VLC is running (launch/terminate are observed), at a low rate.
@MainActor
final class VLCProvider: MediaProvider {
    let bundleID = "org.videolan.vlc"
    let displayName = "VLC"
    var onUpdate: ((MediaActivity?) -> Void)?
    private var lifecycle: AppLifecycleObserver?
    private var activation: AppActivationObserver?
    private lazy var loop = PollLoop(interval: { [weak self] in self?.interval ?? Self.idleInterval },
                                     body: { [weak self] in await self?.poll() })
    private var last: MediaActivity?
    /// Poll fast while something plays or VLC is in front; otherwise VLC is checked rarely
    /// (each poll spawns osascript).
    static let playingInterval: TimeInterval = 3
    static let frontmostInterval: TimeInterval = 4
    static let idleInterval: TimeInterval = 15
    private var interval: TimeInterval {
        if last?.playbackState == .playing { return Self.playingInterval }
        return AppActivationObserver.isFrontmost(bundleID) ? Self.frontmostInterval : Self.idleInterval
    }

    func start() {
        lifecycle = AppLifecycleObserver(bundleID: bundleID, onLaunch: { [weak self] in self?.startPolling() },
                                         onTerminate: { [weak self] in self?.stopPolling() })
        activation = AppActivationObserver(bundleID: bundleID) { [weak self] in self?.loop.pollNow() }
        if isRunning { startPolling() }
    }

    func stop() {
        lifecycle = nil
        activation = nil
        stopPolling()
    }

    private func startPolling() { loop.start() }

    private func stopPolling() {
        loop.stop()
        last = nil
        onUpdate?(nil)
    }

    private func poll() async {
        let sep = "(character id 30)"
        let script = """
        if application "VLC" is running then
          tell application "VLC"
            try
              set n to name of current item
              if n is missing value then return "none"
              return (playing as text) & \(sep) & n & \(sep) & (current time as text) & \(sep) & (duration of current item as text)
            on error
              return "none"
            end try
          end tell
        end if
        return "none"
        """
        guard let out = try? await ScriptRunner.run(script, timeout: 2) else { return }
        let f = out.components(separatedBy: "\u{1E}")
        guard f.count >= 4 else {
            if last != nil { last = nil; onUpdate?(nil) }
            return
        }
        let m = MediaActivity(sourceBundleID: bundleID, sourceName: displayName, title: f[1],
                              playbackState: f[0] == "true" ? .playing : .paused,
                              elapsed: AppleMusicProvider.number(f[2]), positionTimestamp: Date(),
                              duration: AppleMusicProvider.number(f[3]).flatMap { $0 > 0 ? $0 : nil },
                              controls: [.playPause, .next, .previous, .seek])
        // Avoid churn: only publish meaningful changes (position drift is extrapolated by the UI).
        if let last, last.title == m.title, last.playbackState == m.playbackState,
           abs((last.position(at: Date()) ?? 0) - (m.elapsed ?? 0)) < 2 { return }
        last = m
        onUpdate?(m)
    }

    func perform(_ command: MediaCommand) async throws {
        let verb: String
        switch command {
        case .togglePlayPause, .play, .pause: verb = "play" // VLC's `play` toggles
        case .next: verb = "next"
        case .previous: verb = "previous"
        case .seek(let t): verb = "set current time to \(Int(max(0, t)))"
        }
        _ = try await ScriptRunner.run("if application \"VLC\" is running then tell application \"VLC\" to \(verb)")
        await poll()
    }
}

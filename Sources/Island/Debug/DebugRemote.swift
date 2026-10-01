#if DEBUG
import AppKit
import IslandCore

/// DEBUG builds only: lets scripts drive the Island for visual QA, e.g.
/// `scripts/island-debug.sh expand`. Not compiled into release builds.
@MainActor
final class DebugRemote {
    static let name = Notification.Name("dev.island.debug")
    private var observer: NSObjectProtocol?

    init(env: AppEnvironment) {
        observer = DistributedNotificationCenter.default().addObserver(forName: Self.name, object: nil, queue: .main) { [weak env] note in
            let cmd = note.object as? String ?? ""
            MainActor.assumeIsolated {
                guard let env else { return }
                switch cmd {
                case "expand": env.island.expand()
                case "collapse": env.island.collapse()
                case "search": env.island.toggleSearch()
                case "next": env.manager.selectNext()
                case "music": env.manager.submit(.upsert(DebugActivities.music()))
                case "timer": env.timers.handle(.start(duration: 300, label: "Timer"))
                case "download": env.manager.submit(.upsert(DebugActivities.download()))
                case "recording": env.manager.submit(.upsert(DebugActivities.recording()))
                case "critical": env.manager.submit(.upsert(DebugActivities.criticalEvent()))
                case "battery": env.manager.submit(.upsert(DebugActivities.battery()))
                case "clear": env.manager.removeAll()
                case "dump": DebugRemote.dump(env)
                case "settings": env.commands.perform(.openSettings)
                case "debugpanel": env.showDebugPanel()
                case "quicktimer": env.timers.handle(.start(duration: 3, label: "Quick"))
                default:
                    if cmd.hasPrefix("query:") { env.search.query = String(cmd.dropFirst(6)) }
                }
            }
        }
    }
}
extension DebugRemote {
    /// Writes a state snapshot to $TMPDIR/island-debug.txt for scripted QA.
    static func dump(_ env: AppEnvironment) {
        var lines: [String] = []
        lines.append("mode=\(env.island.mode.rawValue) size=\(env.island.islandSize)")
        lines.append("primary=\(env.manager.primary.map { "\($0.id) \($0.priority)" } ?? "none")")
        lines.append("secondaries=\(env.manager.secondaries.map(\.id))")
        if case .media(let m)? = env.manager.activity(id: "media")?.content {
            lines.append("media=\(m.sourceName) | \(m.title) | \(m.artist) | \(m.playbackState) | artwork=\(m.artwork?.count ?? 0)B | pos=\(m.elapsed ?? -1)/\(m.duration ?? -1)")
        }
        lines.append("mediaSources=\(env.media.states.keys.sorted()) current=\(env.media.currentSource ?? "none") error=\(env.media.lastError ?? "none")")
        lines.append("geometry=\(String(describing: env.island.geometry?.notchRect)) notch=\(env.island.geometry?.hasNotch ?? false)")
        lines.append("window=\(env.window.panel.frame) ignoresMouse=\(env.window.panel.ignoresMouseEvents)")
        for e in env.manager.log.suffix(15) { lines.append("log: \(e.message)") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("island-debug.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif

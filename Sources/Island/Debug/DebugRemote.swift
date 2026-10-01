#if DEBUG
import AppKit
import IslandCore

/// DEBUG builds only: lets scripts drive the Island for visual QA, e.g.
/// `scripts/island-debug.sh expand`. Not compiled into release builds.
@MainActor
final class DebugRemote {
    static let name = Notification.Name("dev.island.debug")
    private var observer: NSObjectProtocol?
    private let frames = FrameRecorder()

    init(env: AppEnvironment) {
        observer = DistributedNotificationCenter.default().addObserver(forName: Self.name, object: nil, queue: .main) { [weak env, frames] note in
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
                case "airpods", "airpodspro", "headphones":
                    let name = cmd == "airpods" ? "AirPods" : cmd == "airpodspro" ? "Poshak's AirPods Pro" : "WH-1000XM5"
                    env.manager.submit(.upsert(Activity(id: "device", kind: .device, priority: .high,
                        content: .device(DeviceActivity(name: name, type: .headphones, connected: true)), expiresAt: Date().addingTimeInterval(5))))
                    env.bus.publish(.deviceConnected(name: name))
                case "dump": DebugRemote.dump(env)
                case "settings": env.commands.perform(.openSettings)
                case "debugpanel": env.showDebugPanel()
                case "quicktimer": env.timers.handle(.start(duration: 3, label: "Quick"))
                case "stress":
                    // Run from a timer (not inside this main-queue block) so deferred main-queue work can execute.
                    Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in MainActor.assumeIsolated { StressTest(env: env).run() } }
                default:
                    if cmd.hasPrefix("frames:"), let secs = Double(cmd.dropFirst(7)), let v = env.window.panel.contentView {
                        frames.record(on: v, seconds: secs)
                    }
                    if cmd.hasPrefix("stress:"), let seed = UInt64(cmd.dropFirst(7)) {
                        Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in MainActor.assumeIsolated { StressTest(env: env).run(seed: seed) } }
                    }
                    if cmd.hasPrefix("set:") {
                        let kv = cmd.dropFirst(4).split(separator: "=")
                        let on = kv.count > 1 && kv[1] == "1"
                        switch kv.first ?? "" {
                        case "islandEnabled": env.settings.islandEnabled = on
                        case "hoverExpansion": env.settings.hoverExpansion = on
                        case "reduceMotion": env.settings.forceReduceMotion = on
                        case "reduceTransparency": env.settings.forceReduceTransparency = on
                        case "highContrast": env.settings.forceHighContrast = on
                        case "searchEnabled": env.settings.searchEnabled = on
                        default: break
                        }
                    }
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
        lines.append("polling=\(env.window.isPollingPointer) panelVisible=\(env.window.panel.isVisible) escapeArmed=\(env.window.escapeArmed) key=\(env.window.panel.isKeyWindow) monitors=\(env.window.monitorCount) visible=\(env.window.isVisible) mouseEvents=\(env.window.mouseEventCount) last=\(env.window.lastMouse) inside=\(env.island.mouseInside) hit=\(env.window.interactiveRect)")
        lines.append("hotkey=\(env.features.hotKey?.registered?.display ?? "none") err=\(env.features.hotKey?.lastError ?? 0)")
        lines.append("window=\(env.window.panel.frame) ignoresMouse=\(env.window.panel.ignoresMouseEvents)")
        for e in env.manager.log.suffix(15) { lines.append("log: \(e.message)") }
        for t in env.island.trace.suffix(20) { lines.append("trace: \(t)") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("island-debug.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif

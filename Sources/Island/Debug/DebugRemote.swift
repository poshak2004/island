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
            NSLog("Island debug remote: %@", cmd)
            MainActor.assumeIsolated {
                guard let env else { return }
                switch cmd {
                case "expand": env.island.expand(); NSLog("mode after expand: %@ size %@", env.island.mode.rawValue, NSStringFromSize(env.island.islandSize))
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
                default:
                    if cmd.hasPrefix("query:") { env.search.query = String(cmd.dropFirst(6)) }
                }
            }
        }
    }
}
#endif

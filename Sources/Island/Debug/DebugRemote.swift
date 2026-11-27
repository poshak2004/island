#if DEBUG
import AppKit
import IslandCore
import SwiftUI

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
                case "airpods", "airpodspro", "airpodsmax":
                    // DEBUG: simulate a connection through the real animator with a canned system report.
                    let name = cmd == "airpodsmax" ? "Test AirPods Max" : cmd == "airpodspro" ? "Poshak’s AirPods Pro" : "Test AirPods"
                    let pid = cmd == "airpodsmax" ? 0x201F : cmd == "airpodspro" ? 0x2024 : 0x2019
                    let battery = cmd == "airpodsmax" ? AirPodsBattery(single: 64) : AirPodsBattery(left: 82, right: 79, caseLevel: 61)
                    // The canned report applies to this one simulated connection only; real AirPods
                    // connecting afterwards must read the system's battery levels again. A connect
                    // that would be ignored (a sequence is running) installs nothing.
                    guard env.airPods.phase == .idle else { break }
                    let real = env.airPods.lookup
                    env.airPods.lookup = { [weak airPods = env.airPods] _ in
                        await MainActor.run { airPods?.lookup = real }
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        return BluetoothDeviceReport(name: name, address: nil, productID: pid, vendorID: 0x004C, connected: true, battery: battery)
                    }
                    env.airPods.deviceConnected(name: name)
                case "welcome":
                    // DEBUG: replay the first-run welcome (Done/Escape marks it complete again).
                    env.settings.hasCompletedWelcome = false
                    env.island.presentWelcomeIfNeeded()
                case "welcomedone": env.island.completeWelcome()
                case "keyboard": env.island.toggleWithKeyboard()
                case "airpodsreal": env.airPods.lookup = { await AirPodsInfoProvider.lookup(name: $0) }
                case let c where c.hasPrefix("airpodslive:"):
                    // DEBUG: replay a connection for a real paired device, reading its live system report.
                    env.airPods.lookup = { await AirPodsInfoProvider.lookup(name: $0) }
                    env.airPods.deviceConnected(name: String(c.dropFirst("airpodslive:".count)))
                case "headphones":
                    env.manager.submit(.upsert(Activity(id: "device", kind: .device, priority: .high,
                        content: .device(DeviceActivity(name: "WH-1000XM5", type: .headphones, connected: true)), expiresAt: Date().addingTimeInterval(5))))
                    env.bus.publish(.deviceConnected(name: "WH-1000XM5"))
                case "dump": DebugRemote.dump(env)
                case "settings": env.commands.perform(.openSettings)
                case "snapsettings": SettingsSnapshotter.renderAll(env: env)
                case "samplemorph": MorphSampler.run(env: env)
                case let c where c.hasPrefix("snapwindow:"):
                    SettingsSnapshotter.renderWindow(env: env, paneName: String(c.dropFirst("snapwindow:".count)))
                case let c where c.hasPrefix("snapisland:"):
                    SettingsSnapshotter.renderIsland(env: env, name: String(c.dropFirst("snapisland:".count)))
                case "debugpanel": env.showDebugPanel()
                case "quicktimer": env.timers.handle(.start(duration: 3, label: "Quick"))
                case "prompter":
                    env.teleprompter.start(text: DebugActivities.sampleScript, title: "Product demo", autoplay: true)
                case "prompterstop": env.teleprompter.stop()
                case "shelfdemo":
                    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardizedFileURL
                    env.commands.perform(.shelf(.add(["README.md", "LICENSE", "Package.swift", "Resources/AppIcon.icns"].map { root.appendingPathComponent($0) })))
                case "shelfdrag": env.fileDrags.onChange?(true)
                case "shelfdragend": env.fileDrags.onChange?(false)
                case "shelfclear": env.commands.perform(.shelf(.clear))
                case "homedemo":
                    env.home.eventOverride = HomeEvent(title: "Standup", start: Date().addingTimeInterval(7 * 60),
                                                       joinURL: URL(string: "https://meet.google.com/abc-defg-hij"))
                    let readme = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../README.md").standardizedFileURL
                    env.home.recentDownload = HomeFile(name: "README.md", url: readme, at: Date())
                case "homedemoend": env.home.eventOverride = nil; env.home.recentDownload = nil
                case "homereset": env.settings.homePins = HomePins.defaults
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
                        case "prompterHide": env.settings.teleprompterHideFromCapture = on
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
        lines.append("airpods=\(env.airPods.phase.rawValue) revealed=\(env.airPods.isRevealed)")
        if let t = env.teleprompter.current {
            lines.append(String(format: "prompter=%@ pos=%.2f hoverPaused=%@ voice=%@ listening=%@ sharing=%d",
                                t.state.rawValue, t.position(at: Date()), "\(t.hoverPaused)", "\(t.voiceFollow)", "\(t.listening)",
                                env.window.panel.sharingType.rawValue))
        } else {
            lines.append("prompter=none sharing=\(env.window.panel.sharingType.rawValue)")
        }
        lines.append("hotkey=\(env.features.hotKey?.registered?.display ?? "none") err=\(env.features.hotKey?.lastError ?? 0)")
        lines.append("window=\(env.window.panel.frame) ignoresMouse=\(env.window.panel.ignoresMouseEvents)")
        for e in env.manager.log.suffix(15) { lines.append("log: \(e.message)") }
        for t in env.island.trace.suffix(20) { lines.append("trace: \(t)") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("island-debug.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
/// DEBUG: draws every Settings pane offscreen to PNGs (no screen-recording permission needed), with
/// Experimental off and on, against a throwaway settings store — the user's settings are untouched.
@MainActor
enum SettingsSnapshotter {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/island-qa/settings", isDirectory: true)

    static func renderAll(env: AppEnvironment) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for experimental in [false, true] {
            let suite = UserDefaults(suiteName: "island.snapshots.\(UUID().uuidString)")!
            let scratch = IslandSettings(defaults: suite)
            scratch.experimentalFeatures = experimental
            scratch.aiProvider = experimental ? .anthropic : .none
            for pane in SettingsPane.allCases {
                let view = pane.view(settings: scratch, env: env)
                    .frame(width: SettingsPane.width, height: pane.height)
                    .environment(\.colorScheme, .dark)
                write(view, name: "\(experimental ? "exp-on" : "exp-off")-\(pane.rawValue.lowercased())")
            }
        }
        NSLog("Island: settings snapshots in %@", directory.path)
    }

    /// DEBUG: draws the live Island window's view tree to a PNG (the glass material itself isn't drawn,
    /// so the background shows as clear; content, layout and text are exact).
    /// DEBUG: the real Settings window (title bar and toolbar included), offscreen, to check layout.
    static func renderWindow(env: AppEnvironment, paneName: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pane = SettingsPane.allCases.first { $0.rawValue.lowercased() == paneName.lowercased() } ?? .general
        let w = SettingsWindowController.makeWindow(settings: env.settings, env: env, selecting: pane)
        w.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        w.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        defer { w.orderOut(nil) }
        guard let frame = w.contentView?.superview,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: directory.appendingPathComponent("window-\(pane.rawValue.lowercased()).png"))
    }

    static func renderIsland(env: AppEnvironment, name: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let view = env.window.panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("island-\(name).png"))
    }

    private static func write(_ view: some View, name: String) {
        let size = NSSize(width: 600, height: 640)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI finish a layout pass before drawing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = rep.representation(using: .png, properties: [:])
        try? data?.write(to: directory.appendingPathComponent("\(name).png"))
        window.contentView = nil
    }
}

/// DEBUG: samples the outline's presented size every ~8 ms through an open and a close, and writes
/// "t height width" lines, so motion smoothness (monotonic? overshoot? steps?) can be measured.
@MainActor
enum MorphSampler {
    static let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/island-qa/morph-samples.txt")

    static func run(env: AppEnvironment) {
        var lines: [String] = []
        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let s = env.window.surface.presentedOutlineSize else { return }
                lines.append(String(format: "%.4f %.2f %.2f", CACurrentMediaTime() - start, s.height, s.width))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { env.island.expand() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { env.island.collapse() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            timer.invalidate()
            try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        }
    }
}

#endif

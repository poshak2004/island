import CoreGraphics
import Foundation
@testable import IslandCore

@MainActor
func registerPresentationTests() {
    let S = "Presentation"

    test(S, "idle → compact when an activity arrives") {
        var p = IslandPresentation()
        expectEqual(p.mode, .idle)
        p.handle(.activityAvailabilityChanged(hasActivity: true))
        expectEqual(p.mode, .compact)
    }

    test(S, "hover expands and hover exit collapses") {
        var p = IslandPresentation()
        p.handle(.activityAvailabilityChanged(hasActivity: true))
        p.handle(.hoverBegan)
        expectEqual(p.mode, .expanded)
        expectEqual(p.reason, .hover)
        p.handle(.hoverEnded)
        expectEqual(p.mode, .compact)
    }

    test(S, "hover with expansion disabled does nothing; click expands") {
        var p = IslandPresentation(hoverExpansionEnabled: false)
        p.handle(.activityAvailabilityChanged(hasActivity: true))
        p.handle(.hoverBegan)
        expectEqual(p.mode, .compact)
        p.handle(.click)
        expectEqual(p.mode, .expanded)
        p.handle(.autoCollapse)
        expectEqual(p.mode, .expanded) // still hovering
        p.handle(.hoverEnded)
        expectEqual(p.mode, .compact)
    }

    test(S, "idle hover reveals home surface and returns to idle") {
        var p = IslandPresentation()
        p.handle(.hoverBegan)
        expectEqual(p.mode, .expanded)
        p.handle(.hoverEnded)
        expectEqual(p.mode, .idle)
    }

    test(S, "activity ending while expanded keeps expanded, collapse goes idle") {
        var p = IslandPresentation()
        p.handle(.activityAvailabilityChanged(hasActivity: true))
        p.handle(.click)
        p.handle(.activityAvailabilityChanged(hasActivity: false))
        expectEqual(p.mode, .expanded)
        p.handle(.clickOutside)
        expectEqual(p.mode, .idle)
    }

    test(S, "search toggles and escape exits") {
        var p = IslandPresentation()
        p.handle(.activityAvailabilityChanged(hasActivity: true))
        p.handle(.toggleSearch)
        expectEqual(p.mode, .search)
        p.handle(.hoverEnded)
        expectEqual(p.mode, .search) // search ignores hover exit
        p.handle(.escape)
        expectEqual(p.mode, .compact)
        p.handle(.toggleSearch)
        p.handle(.toggleSearch)
        expectEqual(p.mode, .compact)
    }

    test(S, "transient presentation ends unless hovering") {
        var p = IslandPresentation()
        p.handle(.activityAvailabilityChanged(hasActivity: true))
        p.handle(.presentTransient)
        expectEqual(p.mode, .expanded)
        p.handle(.transientEnded)
        expectEqual(p.mode, .compact)
        p.handle(.presentTransient)
        p.handle(.hoverBegan)
        p.handle(.transientEnded)
        expectEqual(p.mode, .expanded)
    }

    test(S, "transient card ignores clicks elsewhere; Escape still dismisses") {
        var p = IslandPresentation()
        p.handle(.activityAvailabilityChanged(hasActivity: true))
        p.handle(.presentTransient)
        p.handle(.clickOutside)
        expectEqual(p.mode, .expanded)
        p.handle(.escape)
        expectEqual(p.mode, .compact)
    }

    test(S, "command expansion survives hover exit") {
        var p = IslandPresentation()
        p.handle(.activityAvailabilityChanged(hasActivity: true))
        p.handle(.expand)
        p.handle(.hoverEnded)
        expectEqual(p.mode, .expanded)
        p.handle(.collapse)
        expectEqual(p.mode, .compact)
    }

    test(S, "rapid hover in/out is stable") {
        var p = IslandPresentation()
        p.handle(.activityAvailabilityChanged(hasActivity: true))
        for _ in 0..<50 { p.handle(.hoverBegan); p.handle(.hoverEnded) }
        expectEqual(p.mode, .compact)
        expect(!p.hovering)
    }

    test(S, "metrics: expanded > compact > idle, all derived from notch") {
        let m = IslandMetrics(notchSize: CGSize(width: 180, height: 32), hasNotch: true)
        let idle = m.size(mode: .idle, compact: .standard, expanded: .home)
        let compact = m.size(mode: .compact, compact: .standard, expanded: .home)
        let wide = m.size(mode: .compact, compact: .wide, expanded: .home)
        let expanded = m.size(mode: .expanded, compact: .standard, expanded: .media)
        expectEqual(idle, CGSize(width: 180, height: 32))
        expect(compact.width > idle.width && compact.height == 32)
        expect(wide.width > compact.width)
        expect(expanded.width > wide.width && expanded.height > compact.height)
        expect(m.windowSize.width >= expanded.width && m.windowSize.height >= expanded.height)
    }

    test(S, "metrics: window fits every state for many notch sizes and scales") {
        for w in stride(from: 120.0, through: 260, by: 20) {
            for s in [0.8, 1.0, 1.3] {
                let m = IslandMetrics(notchSize: CGSize(width: w, height: 32), hasNotch: true, scale: s)
                for mode in [IslandMode.idle, .compact, .expanded, .search] {
                    let size = m.size(mode: mode, compact: .wide, expanded: .research, searchHeight: 10_000, minimals: 2)
                    // The (possibly offset) Island must stay inside the window on both sides.
                    let offset = abs(m.horizontalOffset(mode: mode, compact: .wide, minimals: 2))
                    let total = size.width + 2 * m.topEarRadius(mode: mode) + 2 * offset
                    expect(total <= m.windowSize.width && size.height <= m.windowSize.height, "w=\(w) s=\(s) \(mode)")
                }
            }
        }
    }

    test(S, "metrics: non-notch idle collapses to zero height") {
        let m = IslandMetrics(notchSize: CGSize(width: 190, height: 24), hasNotch: false)
        expectEqual(m.size(mode: .idle, compact: .standard, expanded: .home).height, 0)
        expect(m.hitRect(islandSize: .zero, offset: 0, mode: .idle).height >= 24)
    }

    test(S, "metrics: clamps invalid input") {
        let m = IslandMetrics(notchSize: CGSize(width: -10, height: CGFloat.nan), hasNotch: true, scale: CGFloat.infinity, expandedCornerRadius: 999)
        expect(m.notchSize.width >= 80 && m.scale == 1 && m.expandedCornerRadius == 48)
    }

    test(S, "metrics: compact stays centred on the notch with secondaries; nothing is squeezed") {
        let m = IslandMetrics(notchSize: CGSize(width: 180, height: 32), hasNotch: true)
        let none = m.size(mode: .compact, compact: .standard, expanded: .home, minimals: 0)
        for n in 1...IslandMetrics.maxMinimals {
            let size = m.size(mode: .compact, compact: .standard, expanded: .home, minimals: n)
            let wings = m.compactWings(.standard, minimals: n)
            expect(size.width > none.width)
            // Balanced: both wings the same width, so the pill is centred on the notch (no sideways shift).
            expectEqual(wings.leading, wings.trailing)
            expectEqual(m.horizontalOffset(mode: .compact, compact: .standard, minimals: n), 0)
            // Room for the primary glyph plus one full minimal slot and its separator on each side.
            expect(wings.trailing >= m.wingWidth(.standard) + m.minimalSlot + m.minimalSeparator, "n=\(n)")
        }
        let r = m.hitRect(islandSize: none, offset: 0, mode: .compact)
        expectEqual(r.midX, 0)
    }

    test(S, "metrics: compact is iPhone-narrow") {
        let m = IslandMetrics(notchSize: CGSize(width: 180, height: 32), hasNotch: true)
        expect(m.size(mode: .compact, compact: .standard, expanded: .home).width <= 180 + 2 * 48)
    }
}

@MainActor
func registerRegressionTests() {
    let S = "Regression"

    test(S, "measured content height drives expanded size, clamped") {
        let m = IslandMetrics(notchSize: CGSize(width: 180, height: 32), hasNotch: true)
        let est = m.size(mode: .expanded, compact: .standard, expanded: .media)
        let measured = m.size(mode: .expanded, compact: .standard, expanded: .media, measuredContent: 150)
        expectEqual(measured.height, 32 + IslandMetrics.expandedTopPadding + 150 + IslandMetrics.expandedBottomPadding)
        expect(est.height != measured.height)
        expect(m.size(mode: .expanded, compact: .standard, expanded: .media, measuredContent: 10_000).height <= m.windowSize.height)
    }

    test(S, "selectNext cycles every visible activity in a stable order") {
        let mgr = ActivityManager(clock: { Date(timeIntervalSince1970: 0) })
        mgr.schedulesExpiry = false
        for (i, id) in ["a", "b", "c"].enumerated() {
            mgr.submit(.upsert(Activity(id: id, kind: .custom, priority: i == 2 ? .low : .normal, content: .event(SystemEventActivity(symbol: "x", title: id)))))
        }
        var seen: [String] = []
        for _ in 0..<6 { seen.append(mgr.primary!.id); mgr.selectNext() }
        expectEqual(seen, ["a", "b", "c", "a", "b", "c"])
    }

    test(S, "selectPrevious walks back through the same order (keyboard ←)") {
        let mgr = ActivityManager(clock: { Date(timeIntervalSince1970: 0) })
        mgr.schedulesExpiry = false
        for (i, id) in ["a", "b", "c"].enumerated() {
            mgr.submit(.upsert(Activity(id: id, kind: .custom, priority: i == 2 ? .low : .normal, content: .event(SystemEventActivity(symbol: "x", title: id)))))
        }
        var seen: [String] = []
        for _ in 0..<4 { seen.append(mgr.primary!.id); mgr.selectPrevious() }
        expectEqual(seen, ["a", "c", "b", "a"])
    }

    test(S, "a 4th activity is reachable: next/previous cycle every live activity, and overflow is counted") {
        let mgr = ActivityManager(clock: { Date(timeIntervalSince1970: 0) })
        mgr.schedulesExpiry = false
        for id in ["a", "b", "c", "d"] {
            mgr.submit(.upsert(Activity(id: id, kind: .custom, priority: .normal, content: .event(SystemEventActivity(symbol: "x", title: id)))))
        }
        expectEqual(mgr.secondaries.count, 2)
        expectEqual(mgr.overflowCount, 1)
        var seen: [String] = []
        for _ in 0..<4 { seen.append(mgr.primary!.id); mgr.selectNext() }
        expectEqual(seen, ["a", "b", "c", "d"])
        expectEqual(mgr.primary!.id, "a") // wrapped around past the 4th
        mgr.selectPrevious()
        expectEqual(mgr.primary!.id, "d") // and back to it
    }

    test(S, "VoiceOver hears new events, not chatter (music changes, clipboard, search)") {
        for k in [ActivityKind.timer, .download, .recording, .call, .battery, .network, .device, .calendar, .notification, .custom, .teleprompter, .shelf] {
            expect(k.announcesArrival, "\(k) should be announced")
        }
        for k in [ActivityKind.media, .clipboard, .search] { expect(!k.announcesArrival, "\(k) should stay quiet") }
    }

    test(S, "quiet mode: high-priority arrivals stop interrupting; critical still gets through") {
        func a(_ p: ActivityPriority) -> Activity {
            Activity(id: "x", kind: .battery, priority: p, content: .event(SystemEventActivity(symbol: "x", title: "x")))
        }
        func priority(_ u: ActivityUpdate) -> ActivityPriority? { if case .upsert(let a) = u { return a.priority }; return nil }
        expectEqual(priority(ActivityUpdate.upsert(a(.high)).quieted()), .normal)
        expectEqual(priority(ActivityUpdate.upsert(a(.critical)).quieted()), .critical)
        expectEqual(priority(ActivityUpdate.upsert(a(.low)).quieted()), .low)
        if case .remove(let id) = ActivityUpdate.remove(id: "x").quieted() { expectEqual(id, "x") } else { expect(false) }
        let d = UserDefaults(suiteName: "island.tests.\(UUID().uuidString)")!
        let s = IslandSettings(defaults: d)
        expectEqual(s.quietMode, false)
        s.quietMode = true
        expectEqual(IslandSettings(defaults: d).quietMode, true)
    }

    test(S, "hide-in-full-screen (on) and per-activity quiet kinds (none) persist") {
        let d = UserDefaults(suiteName: "island.tests.\(UUID().uuidString)")!
        let s = IslandSettings(defaults: d)
        expectEqual(s.hideInFullScreen, true)
        expectEqual(s.quietKinds, [])
        expect(!s.isQuiet(.battery))
        s.hideInFullScreen = false
        s.quietKinds = [.battery, .network]
        let r = IslandSettings(defaults: d)
        expectEqual(r.hideInFullScreen, false)
        expectEqual(r.quietKinds, [.battery, .network])
        expect(r.isQuiet(.battery) && !r.isQuiet(.timer))
        r.quietKinds = []
        r.quietMode = true
        expect(r.isQuiet(.timer), "global quiet mode covers every kind")
    }

    test(S, "per-activity quiet: only the chosen kinds are quieted") {
        let battery = Activity(id: "b", kind: .battery, priority: .high, content: .event(SystemEventActivity(symbol: "x", title: "b")))
        let timer = Activity(id: "t", kind: .timer, priority: .high, content: .event(SystemEventActivity(symbol: "x", title: "t")))
        func priority(_ u: ActivityUpdate) -> ActivityPriority? { if case .upsert(let a) = u { return a.priority }; return nil }
        let quiet: (ActivityKind) -> Bool = { $0 == .battery }
        expectEqual(priority(ActivityUpdate.upsert(battery).quieted(when: quiet)), .normal)
        expectEqual(priority(ActivityUpdate.upsert(timer).quieted(when: quiet)), .high)
    }

    test(S, "names running apps that claim ⌥Space by default") {
        let running: Set<String> = ["com.raycast.macos", "com.apple.Safari"]
        expectEqual(ShortcutConflicts.likelyOwners(of: .defaultSearch, running: running), ["Raycast"])
        let other = IslandShortcut(keyCode: 49, carbonModifiers: 0x1000, display: "⌃Space")
        expectEqual(ShortcutConflicts.likelyOwners(of: other, running: running), [])
        expectEqual(ShortcutConflicts.likelyOwners(of: .defaultSearch, running: ["com.apple.Safari"]), [])
    }

    test(S, "the open-Island shortcut defaults to ⌃⌥I and persists") {
        let d = UserDefaults(suiteName: "island.tests.\(UUID().uuidString)")!
        let s = IslandSettings(defaults: d)
        expectEqual(s.islandShortcut, .defaultIsland)
        expectEqual(IslandShortcut.defaultIsland.display, "⌃⌥I")
        let custom = IslandShortcut(keyCode: 31, carbonModifiers: 0x1800, display: "⌃⌥O")
        s.islandShortcut = custom
        expectEqual(IslandSettings(defaults: d).islandShortcut, custom)
    }

    test(S, "manager notifies synchronously on every change") {
        let mgr = ActivityManager()
        mgr.schedulesExpiry = false
        var calls = 0
        mgr.onChange = { calls += 1 }
        mgr.submit(.upsert(Activity(id: "x", kind: .custom, priority: .normal, content: .event(SystemEventActivity(symbol: "x", title: "x")))))
        expectEqual(calls, 1)
        mgr.removeAll()
        expectEqual(calls, 2)
        expect(mgr.primary == nil)
    }

    test(S, "one unreadable setting doesn't reset all the others") {
        let d = UserDefaults(suiteName: "island.tests.\(UUID().uuidString)")!
        let raw = #"{"glassIntensity": 0.3, "display": {"future": "value"}, "aiProvider": "fromTheFuture", "hoverExpansion": false}"#
        d.set(raw.data(using: .utf8), forKey: "island.settings.v1")
        let s = IslandSettings(defaults: d)
        expectEqual(s.glassIntensity, 0.3)
        expectEqual(s.hoverExpansion, false)
        expect(d.data(forKey: "island.settings.v1.unreadable") != nil, "the original is kept for recovery")
    }

    test(S, "experimental features are off by default and gate web, AI and automation") {
        let d = UserDefaults(suiteName: "island.tests.\(UUID().uuidString)")!
        let s = IslandSettings(defaults: d)
        expectEqual(s.experimentalFeatures, false)
        s.webSearchEnabled = true
        s.aiProvider = .openAI
        expectEqual(s.effectiveWebSearch, false)
        expectEqual(s.effectiveAIProvider, .none)
        expectEqual(s.automationEnabled, false)
        s.experimentalFeatures = true
        expectEqual(s.effectiveWebSearch, true)
        expectEqual(s.effectiveAIProvider, .openAI)
        expectEqual(s.automationEnabled, true)
    }

    test(S, "existing AI users keep their features after the experimental switch arrives") {
        let d = UserDefaults(suiteName: "island.tests.\(UUID().uuidString)")!
        d.set(#"{"aiProvider": "openAI"}"#.data(using: .utf8), forKey: "island.settings.v1")
        expectEqual(IslandSettings(defaults: d).experimentalFeatures, true)
        let fresh = UserDefaults(suiteName: "island.tests.\(UUID().uuidString)")!
        fresh.set(#"{"glassIntensity": 0.5}"#.data(using: .utf8), forKey: "island.settings.v1")
        expectEqual(IslandSettings(defaults: fresh).experimentalFeatures, false)
    }

    test(S, "welcome shows once on a fresh install, never to existing users") {
        let fresh = UserDefaults(suiteName: "island.tests.\(UUID().uuidString)")!
        let s = IslandSettings(defaults: fresh)
        expectEqual(s.hasCompletedWelcome, false)
        s.hasCompletedWelcome = true
        expectEqual(IslandSettings(defaults: fresh).hasCompletedWelcome, true)
        let existing = UserDefaults(suiteName: "island.tests.\(UUID().uuidString)")!
        existing.set(#"{"glassIntensity": 0.5}"#.data(using: .utf8), forKey: "island.settings.v1")
        expectEqual(IslandSettings(defaults: existing).hasCompletedWelcome, true)
    }

    test(S, "old default hover delay migrates") {
        let d = UserDefaults(suiteName: "island.tests.\(UUID().uuidString)")!
        d.set(#"{"hoverDelay": 0.12}"#.data(using: .utf8), forKey: "island.settings.v1")
        expectEqual(IslandSettings(defaults: d).hoverDelay, 0.06)
        d.set(#"{"hoverDelay": 0.3}"#.data(using: .utf8), forKey: "island.settings.v1")
        expectEqual(IslandSettings(defaults: d).hoverDelay, 0.3)
    }
}

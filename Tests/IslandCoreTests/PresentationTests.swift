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
                    let size = m.size(mode: mode, compact: .wide, expanded: .research, searchHeight: 10_000)
                    let total = size.width + 2 * m.topEarRadius(mode: mode) + (mode == .compact ? 2 * (m.bubbleDiameter + m.bubbleSpacing) : 0)
                    expect(total <= m.windowSize.width && size.height <= m.windowSize.height, "w=\(w) s=\(s) \(mode)")
                }
            }
        }
    }

    test(S, "metrics: non-notch idle collapses to zero height") {
        let m = IslandMetrics(notchSize: CGSize(width: 190, height: 24), hasNotch: false)
        expectEqual(m.size(mode: .idle, compact: .standard, expanded: .home).height, 0)
        expect(m.hitRect(islandSize: .zero, bubbles: 0, mode: .idle).height >= 24)
    }

    test(S, "metrics: clamps invalid input") {
        let m = IslandMetrics(notchSize: CGSize(width: -10, height: CGFloat.nan), hasNotch: true, scale: CGFloat.infinity, expandedCornerRadius: 999)
        expect(m.notchSize.width >= 80 && m.scale == 1 && m.expandedCornerRadius == 48)
    }

    test(S, "metrics: hit rect includes bubbles only in compact") {
        let m = IslandMetrics(notchSize: CGSize(width: 180, height: 32), hasNotch: true)
        let size = m.size(mode: .compact, compact: .standard, expanded: .home)
        let r0 = m.hitRect(islandSize: size, bubbles: 0, mode: .compact)
        let r2 = m.hitRect(islandSize: size, bubbles: 2, mode: .compact)
        expect(r2.width > r0.width)
        let e = m.hitRect(islandSize: size, bubbles: 2, mode: .expanded)
        expectEqual(e.width, r0.width)
    }
}

import SwiftUI

/// The Island's motion system — one family of springs, shared by SwiftUI content and the Core
/// Animation outline (`IslandSurfaceView`), so shape and content always move on the same timing.
///
/// HIG › Motion: brief, precise, non-bouncy for frequent interactions; a little swell only on open.
/// Apple closes faster than it opens. Every duration scales with Settings › Animation speed.
enum IslandAnimation {
    /// A spring as response (s) + damping ratio — the form both SwiftUI and `CASpringAnimation` take.
    struct SpringSpec: Equatable {
        let response: Double
        let dampingRatio: Double
    }

    /// Outline springs (also used by `IslandSurfaceView`).
    static let open = SpringSpec(response: 0.46, dampingRatio: 0.74)   // soft open with a gentle swell
    static let close = SpringSpec(response: 0.34, dampingRatio: 1.0)   // quicker, settles without bounce
    static let morph = SpringSpec(response: 0.42, dampingRatio: 0.84)  // in-place resizes

    static func clampedSpeed(_ speed: Double) -> Double { max(0.5, min(2, speed)) }

    /// Content swaps inside the open Island (home ↔ activity, tab changes).
    static func contentChange(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.25)
    }

    /// Resizes of the open Island — the same spring the outline uses, so the clip and content agree.
    static func morph(reduceMotion: Bool, speed: Double) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.2) }
        return .spring(response: morph.response / clampedSpeed(speed), dampingFraction: morph.dampingRatio)
    }

    /// Content arriving: waits only a beat for the glass, then settles without bounce.
    static func contentIn(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.3, bounce: 0).delay(0.05)
    }

    /// Content leaving: quick, but a spring rather than a cut, so it shrinks with the shape.
    static func contentOut(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.14, bounce: 0)
    }

    /// Insert/removal transition for content inside the morphing surface. Removal is quick and
    /// insertion follows it, so compact and expanded content never overlap.
    static func contentTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                .animation(contentIn(reduceMotion: false)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                .animation(contentOut(reduceMotion: false)))
    }
}

import SwiftUI

/// Single place for Island motion. Springs are interruptible: retargeting mid-flight preserves velocity,
/// so hovering in/out quickly never "restarts" the morph.
enum IslandAnimation {
    /// General morph (activity changes, resizes).
    static func morph(reduceMotion: Bool, speed: Double) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.18) }
        let s = max(0.5, min(2, speed))
        return .spring(response: 0.36 / s, dampingFraction: 0.84)
    }

    /// Opening: quick with a hint of overshoot, like the iPhone island.
    static func expand(reduceMotion: Bool, speed: Double) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.18) }
        return .spring(response: 0.34 / max(0.5, min(2, speed)), dampingFraction: 0.74)
    }

    /// Closing: crisp, no bounce, so the Island settles cleanly into the notch.
    static func collapse(reduceMotion: Bool, speed: Double) -> Animation {
        if reduceMotion { return .easeIn(duration: 0.16) }
        return .spring(response: 0.30 / max(0.5, min(2, speed)), dampingFraction: 0.95)
    }

    static func content(reduceMotion: Bool, speed: Double) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.15) }
        return .spring(response: 0.36 / max(0.5, min(2, speed)), dampingFraction: 0.9)
    }

    /// Insert/removal transition for content inside the morphing surface.
    static func contentTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .top)).animation(.spring(response: 0.32, dampingFraction: 0.88).delay(0.05)),
            removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).animation(.easeOut(duration: 0.1))
        )
    }
}

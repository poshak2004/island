import SwiftUI

/// Single place for Island motion. Springs are interruptible: retargeting mid-flight preserves velocity,
/// so hovering in/out quickly never "restarts" the morph.
enum IslandAnimation {
    static func morph(reduceMotion: Bool, speed: Double) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.18) }
        let s = max(0.5, min(2, speed))
        return .spring(response: 0.44 / s, dampingFraction: 0.80, blendDuration: 0.1)
    }

    static func content(reduceMotion: Bool, speed: Double) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.15) }
        return .spring(response: 0.36 / max(0.5, min(2, speed)), dampingFraction: 0.9)
    }

    /// Insert/removal transition for content inside the morphing surface.
    static func contentTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.86, anchor: .top)).animation(.spring(response: 0.38, dampingFraction: 0.85).delay(0.06)),
            removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(.easeOut(duration: 0.12))
        )
    }
}

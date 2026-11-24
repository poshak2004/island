import Foundation

/// Analytic damped spring, normalized to travel 0 → 1 — the same model `CASpringAnimation` uses
/// (mass 1, stiffness (2π/response)², damping 4π·ζ/response).
///
/// Used to retarget a morph mid-flight without losing speed: read the running spring's velocity
/// at "now", convert it into the next spring's normalized units, and pass it as `initialVelocity`.
/// That is what makes an interrupted Apple-style spring feel continuous instead of stalling.
public struct SpringMotion: Equatable, Sendable {
    public let omega: Double
    public let dampingRatio: Double
    /// Normalized: fractions of the total distance per second, positive toward the target.
    public let initialVelocity: Double

    public init(response: Double, dampingRatio: Double, initialVelocity: Double) {
        self.init(omega: 2 * .pi / max(0.01, response), dampingRatio: dampingRatio, initialVelocity: initialVelocity)
    }

    public init(omega: Double, dampingRatio: Double, initialVelocity: Double) {
        self.omega = max(0.01, omega)
        self.dampingRatio = max(0.01, dampingRatio)
        self.initialVelocity = initialVelocity
    }

    /// Fraction of the way to the target after `t` seconds.
    public func position(at t: Double) -> Double {
        let (w, z, v0) = (omega, dampingRatio, initialVelocity)
        if z < 1 {
            let wd = w * (1 - z * z).squareRoot()
            let b = (z * w - v0) / wd
            return 1 - exp(-z * w * t) * (cos(wd * t) + b * sin(wd * t))
        }
        // Critically (and, clamped, over-) damped.
        return 1 - exp(-w * t) * (1 + (w - v0) * t)
    }

    /// Fractions of the distance per second after `t` seconds.
    public func velocity(at t: Double) -> Double {
        let (w, z, v0) = (omega, dampingRatio, initialVelocity)
        if z < 1 {
            let wd = w * (1 - z * z).squareRoot()
            let b = (z * w - v0) / wd
            let e = exp(-z * w * t)
            return e * ((z * w - b * wd) * cos(wd * t) + (z * w * b + wd) * sin(wd * t))
        }
        let e = exp(-w * t)
        return e * (w * (1 + (w - v0) * t) - (w - v0))
    }

    /// Converts an on-screen speed (points/s, positive = increasing value) into the normalized
    /// `initialVelocity` of a new spring running `from` → `to`.
    public static func normalizedVelocity(pointsPerSecond: Double, from: Double, to: Double) -> Double {
        let distance = to - from
        guard abs(distance) > 0.5 else { return 0 }
        return pointsPerSecond / distance
    }
}

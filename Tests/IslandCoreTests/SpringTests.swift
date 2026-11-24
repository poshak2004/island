import Foundation
@testable import IslandCore

@MainActor
func registerSpringTests() {
    let S = "Spring"

    test(S, "starts at 0 with its initial velocity and settles at 1") {
        let s = SpringMotion(response: 0.42, dampingRatio: 0.84, initialVelocity: 0)
        expect(abs(s.position(at: 0)) < 1e-9)
        expect(abs(s.velocity(at: 0)) < 1e-9)
        expect(abs(s.position(at: 3) - 1) < 1e-3)
        expect(abs(s.velocity(at: 3)) < 1e-2)
        let moving = SpringMotion(response: 0.42, dampingRatio: 0.84, initialVelocity: 2.5)
        expect(abs(moving.velocity(at: 0) - 2.5) < 1e-9)
    }

    test(S, "velocity is the derivative of position (underdamped and critical)") {
        for s in [SpringMotion(response: 0.46, dampingRatio: 0.74, initialVelocity: 1.2),
                  SpringMotion(response: 0.3, dampingRatio: 1, initialVelocity: -0.5)] {
            for t in stride(from: 0.02, to: 0.6, by: 0.07) {
                let h = 1e-5
                let numeric = (s.position(at: t + h) - s.position(at: t - h)) / (2 * h)
                expect(abs(numeric - s.velocity(at: t)) < 1e-3, "t=\(t) numeric \(numeric) vs \(s.velocity(at: t))")
            }
        }
    }

    test(S, "retargeting mid-flight carries the on-screen speed into the new spring") {
        // Opening 0 → 100, interrupted at t = 0.1 s and sent back to 0.
        let open = SpringMotion(response: 0.46, dampingRatio: 0.74, initialVelocity: 0)
        let t = 0.1
        let here = 100 * open.position(at: t)
        let speed = 100 * open.velocity(at: t)            // points per second, toward +100
        let v = SpringMotion.normalizedVelocity(pointsPerSecond: speed, from: here, to: 0)
        // Moving away from the new target (0) → negative normalized velocity, scaled by the new distance.
        expect(v < 0)
        expect(abs(v - (-speed / here)) < 1e-9)
        expectEqual(SpringMotion.normalizedVelocity(pointsPerSecond: 500, from: 10, to: 10), 0)
    }
}

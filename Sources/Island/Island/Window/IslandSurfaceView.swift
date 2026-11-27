import AppKit
import QuartzCore
import IslandCore
import SwiftUI

/// The Island's morphing surface, driven entirely by Core Animation.
///
/// The outline, its glass, the dark tint, the hairline and the content clip are all layers whose
/// `path`/`opacity` spring in the render server (`CASpringAnimation`). The app does no per-frame work
/// while the Island opens or closes — that is what makes the motion smooth. SwiftUI renders only the
/// content, laid out once at its final size, inside `contentHost`.
@MainActor
final class IslandSurfaceView: NSView {
    struct Geometry: Equatable {
        var width: CGFloat          // body width including ears
        var height: CGFloat
        var earRadius: CGFloat
        var bottomRadius: CGFloat
        var offsetX: CGFloat
        var glass: CGFloat          // 0 = solid black, 1 = full glass
        var clearGlass: Bool
        /// Black layer between the glass and the content: 1 = solid, ~0.35 = Apple's clear-glass dim.
        var dimming: CGFloat
        var visible: Bool
        var highContrast: Bool
    }

    enum Motion { case open, close, morph, none }

    let contentHost: NSView
    private let backgroundContainer = FlippedView()
    private let glassView: NSView
    private let tintLayer = CALayer()
    private let edgeLayer = CAShapeLayer()
    private let backgroundMask = CAShapeLayer()
    private let contentMask = CAShapeLayer()
    private(set) var current: Geometry?
    /// The morph in flight, so a retarget can carry its on-screen speed into the next spring.
    private var flight: Flight?
    private var glassHideWork: DispatchWorkItem?
    private struct Flight {
        let start: CFTimeInterval
        let spring: SpringMotion
        let duration: CFTimeInterval
        let from: CGSize
        let to: CGSize
    }
    var reduceMotion = false
    var speed: Double = 1

    init(contentHost: NSView) {
        self.contentHost = contentHost
        if #available(macOS 26, *) {
            let g = NSGlassEffectView()
            g.style = .regular
            glassView = g
        } else {
            let v = NSVisualEffectView()
            v.material = .hudWindow
            v.blendingMode = .behindWindow
            v.state = .active
            v.appearance = NSAppearance(named: .darkAqua)
            glassView = v
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        backgroundContainer.wantsLayer = true
        backgroundContainer.layer?.mask = backgroundMask
        addSubview(backgroundContainer)
        backgroundContainer.addSubview(glassView)
        tintLayer.backgroundColor = NSColor.black.cgColor
        backgroundContainer.layer?.addSublayer(tintLayer)

        edgeLayer.fillColor = nil
        edgeLayer.lineWidth = 0.75
        edgeLayer.strokeColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.addSublayer(edgeLayer)

        contentHost.wantsLayer = true
        contentHost.layer?.mask = contentMask
        addSubview(contentHost)
        for l in [backgroundMask, contentMask, edgeLayer] { l.actions = Self.noImplicitActions }
        tintLayer.actions = Self.noImplicitActions
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        for v in [backgroundContainer, glassView, contentHost] { v.frame = bounds }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.frame = bounds
        for l in [backgroundMask, contentMask, edgeLayer] { l.frame = bounds }
        CATransaction.commit()
        if let current { apply(current, motion: .none) }
    }

    // MARK: Morph

    func apply(_ g: Geometry, motion: Motion) {
        let previous = current
        current = g
        guard bounds.width > 0 else { return }
        let canvas = CGRect(origin: .zero, size: bounds.size)
        let outline = shape(g, ears: true).path(in: canvas).cgPath
        let clip = shape(g, ears: false).path(in: canvas).cgPath
        let tint: Float = g.visible ? Float(g.dimming) : 0
        let glassOpacity: Float = g.visible ? Float(min(1, g.glass * 1.6)) : 0
        let edgeOpacity: Float = g.visible ? Float(g.highContrast ? 1 : (g.glass > 0.001 ? 1 : 0)) : 0
        edgeLayer.strokeColor = g.highContrast ? NSColor.white.withAlphaComponent(0.85).cgColor : NSColor.white.withAlphaComponent(0.14 * g.glass).cgColor
        edgeLayer.lineWidth = g.highContrast ? 1.5 : 0.75
        if #available(macOS 26, *), let glass = glassView as? NSGlassEffectView {
            glass.style = g.clearGlass ? .clear : .regular
        }

        let fade = motion == .none || previous == nil ? nil : spring(for: motion)
        // Reduce Motion: the shape changes in place and only opacity animates (HIG › Motion —
        // replace zooming and resizing with dissolves), so content never overlaps a growing shell.
        let morph = reduceMotion ? nil : fade.map { retargeted($0, from: previous, to: g) }
        if morph == nil { flight = nil }
        animate(backgroundMask, "path", to: outline, with: morph)
        animate(edgeLayer, "path", to: outline, with: morph)
        animate(contentMask, "path", to: clip, with: morph)
        // Shading never bounces: an overshooting spring on the dimming/glass opacity made a dark band
        // pulse across the Island while it moved. Same timing as the shape, critically damped.
        let shade = fade.map(Self.critical)
        animate(tintLayer, "opacity", to: tint, with: shade)
        animate(glassView.layer, "opacity", to: glassOpacity, with: shade)
        updateGlassHidden(visible: glassOpacity > 0, after: fade?.duration ?? 0)
        animate(edgeLayer, "opacity", to: edgeOpacity, with: shade)
        if motion == .open || motion == .close { fadeInContent(opening: motion == .open) }
    }

    /// A copy of `template` whose initial velocity continues the morph already on screen, so
    /// interrupting an open with a close (or vice versa) never stalls the shape to zero speed.
    private func retargeted(_ template: CASpringAnimation, from previous: Geometry?, to g: Geometry) -> CASpringAnimation {
        let now = CACurrentMediaTime()
        let target = CGSize(width: g.width, height: g.height)
        var here = previous.map { CGSize(width: $0.width, height: $0.height) } ?? target
        var speed = CGSize.zero
        if let f = flight, now - f.start < f.duration {
            let t = now - f.start
            let p = f.spring.position(at: t), v = f.spring.velocity(at: t)
            here = CGSize(width: f.from.width + p * (f.to.width - f.from.width),
                          height: f.from.height + p * (f.to.height - f.from.height))
            speed = CGSize(width: v * (f.to.width - f.from.width), height: v * (f.to.height - f.from.height))
        } else if let f = flight {
            here = f.to
        }
        // Use the axis that travels further in the new morph as the reference distance.
        let useHeight = abs(target.height - here.height) >= abs(target.width - here.width)
        let raw = useHeight
            ? SpringMotion.normalizedVelocity(pointsPerSecond: speed.height, from: here.height, to: target.height)
            : SpringMotion.normalizedVelocity(pointsPerSecond: speed.width, from: here.width, to: target.width)
        let v0 = min(Self.maxRetargetVelocity, max(-Self.maxRetargetVelocity, raw))
        let a = template.copy() as! CASpringAnimation
        a.initialVelocity = v0
        a.duration = a.settlingDuration
        let omega = (a.stiffness / a.mass).squareRoot()
        let zeta = a.damping / (2 * (a.stiffness * a.mass).squareRoot())
        flight = Flight(start: now, spring: SpringMotion(omega: omega, dampingRatio: zeta, initialVelocity: v0),
                        duration: a.duration, from: here, to: target)
        return a
    }

    /// A fully transparent blur still costs the window server a backdrop pass every frame, so the
    /// glass view is hidden once it has faded out (compact, solid modes) and shown before it fades in.
    private func updateGlassHidden(visible: Bool, after delay: CFTimeInterval) {
        glassHideWork?.cancel()
        glassHideWork = nil
        guard !visible else { glassView.isHidden = false; return }
        guard delay > 0 else { glassView.isHidden = true; return }
        let work = DispatchWorkItem { [weak self] in self?.glassView.isHidden = true }
        glassHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// The content arrives with a fade timed to the shape, in the render server alongside the outline.
    private func fadeInContent(opening: Bool) {
        guard let layer = contentHost.layer else { return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 0
        a.toValue = 1
        a.duration = (opening ? 0.26 : 0.18) / max(0.5, min(2, speed))
        a.beginTime = CACurrentMediaTime() + (opening ? 0.05 : 0.08) // a beat for the glass to grow first
        a.fillMode = .backwards
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        a.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        layer.add(a, forKey: "contentFade")
    }

    /// Keeps a near-zero remaining distance from turning a modest speed into a violent kick.
    private static let maxRetargetVelocity: Double = 8

    private func shape(_ g: Geometry, ears: Bool) -> IslandShape {
        let s = IslandShape(earRadius: g.earRadius, bottomRadius: g.bottomRadius, width: g.width, height: g.height, offsetX: g.offsetX)
        return ears ? s : s.withoutEars
    }

    /// Spring from the layer's *current on-screen* value, so interrupting a morph never jumps.
    private func animate(_ layer: CALayer?, _ key: String, to value: Any, with template: CASpringAnimation?) {
        guard let layer else { return }
        let from = layer.presentation()?.value(forKeyPath: key) ?? layer.value(forKeyPath: key)
        layer.setValue(value, forKeyPath: key)
        guard let template, let from else { layer.removeAnimation(forKey: key); return }
        let a = template.copy() as! CASpringAnimation
        a.keyPath = key
        a.fromValue = from
        a.toValue = value
        layer.add(a, forKey: key)
    }

    /// The same response as `template`, with no overshoot (damping ratio 1).
    private static func critical(_ template: CASpringAnimation) -> CASpringAnimation {
        let a = template.copy() as! CASpringAnimation
        a.damping = 2 * (a.stiffness * a.mass).squareRoot()
        a.initialVelocity = 0
        a.duration = a.settlingDuration
        return a
    }

    private func spring(for motion: Motion) -> CASpringAnimation {
        let a = CASpringAnimation()
        if reduceMotion {
            a.mass = 1; a.stiffness = 400; a.damping = 40 // critically damped, short
        } else {
            let s = IslandAnimation.clampedSpeed(speed)
            // The shared motion tokens: soft open with a gentle swell, a quicker settled close.
            let spec = switch motion {
            case .open: IslandAnimation.open
            case .close: IslandAnimation.close
            default: IslandAnimation.morph
            }
            let (response, damping) = (spec.response / s, spec.dampingRatio)
            a.mass = 1
            a.stiffness = pow(2 * .pi / response, 2)
            a.damping = 4 * .pi * damping / response
        }
        a.initialVelocity = 0
        a.duration = a.settlingDuration
        a.fillMode = .backwards
        a.isRemovedOnCompletion = true
        // Run at the display's full rate (120 Hz on ProMotion). Left to the default, the outline could
        // step at 60 fps beside smoother content — the jitter people noticed.
        a.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        return a
    }

    #if DEBUG
    /// QA: the outline's on-screen (presentation) size right now, to measure motion smoothness.
    var presentedDimming: Float { tintLayer.presentation()?.opacity ?? tintLayer.opacity }
    var presentedOutlineSize: CGSize? {
        (backgroundMask.presentation()?.path ?? backgroundMask.path)?.boundingBoxOfPath.size
    }
    #endif

    private static let noImplicitActions: [String: CAAction] = [
        "path": NSNull(), "opacity": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull(),
    ]
}

/// Top-left origin, so mask paths share the Island's coordinate space.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

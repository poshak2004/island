import AppKit
import QuartzCore
import SwiftUI

/// Now-playing equalizer driven entirely by Core Animation: the bars animate in the render server,
/// so a playing track costs Island essentially no CPU (a SwiftUI symbol effect re-renders every frame).
struct EqualizerView: NSViewRepresentable {
    var playing: Bool
    var color: NSColor = .white
    var reduceMotion = false

    func makeNSView(context: Context) -> EqualizerNSView { EqualizerNSView() }

    func updateNSView(_ v: EqualizerNSView, context: Context) {
        v.update(playing: playing && !reduceMotion, color: color)
    }
}

final class EqualizerNSView: NSView {
    private var bars: [CALayer] = []
    private var animating = false
    private static let durations: [CFTimeInterval] = [0.42, 0.31, 0.47, 0.36]
    private static let restScale: CGFloat = 0.3

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<4 {
            let bar = CALayer()
            bar.cornerRadius = 1
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 13) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let w: CGFloat = 2, gap: CGFloat = 2
        let total = CGFloat(bars.count) * w + CGFloat(bars.count - 1) * gap
        var x = (bounds.width - total) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in bars {
            bar.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
            bar.position = CGPoint(x: x + w / 2, y: bounds.midY)
            if !animating { bar.transform = CATransform3DMakeScale(1, Self.restScale, 1) }
            x += w + gap
        }
        CATransaction.commit()
    }

    func update(playing: Bool, color: NSColor) {
        for bar in bars { bar.backgroundColor = color.cgColor }
        guard playing != animating else { return }
        animating = playing
        for (i, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            if playing {
                let a = CABasicAnimation(keyPath: "transform.scale.y")
                a.fromValue = 0.25
                a.toValue = 1.0
                a.duration = Self.durations[i % Self.durations.count]
                a.autoreverses = true
                a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                a.beginTime = CACurrentMediaTime() + Double(i) * 0.07
                bar.add(a, forKey: "eq")
                bar.transform = CATransform3DIdentity
            } else {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.2)
                bar.transform = CATransform3DMakeScale(1, Self.restScale, 1)
                CATransaction.commit()
            }
        }
    }
}

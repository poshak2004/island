import CoreGraphics
import Foundation

/// How wide the compact wings need to be for the current primary activity.
public enum CompactStyle: Equatable, Sendable {
    /// Icon on the left, short value on the right (timer, download, battery…).
    case standard
    /// Artwork + title on the left (media).
    case wide
}

/// Content-driven expanded heights.
public enum ExpandedStyle: Equatable, Sendable {
    case home, media, timer, download, event, research
}

/// All Island geometry, derived from the notch. Nothing here is hard-coded to a screen.
public struct IslandMetrics: Equatable, Sendable {
    public var notchSize: CGSize
    public var hasNotch: Bool
    public var scale: CGFloat
    public var expandedCornerRadius: CGFloat

    public init(notchSize: CGSize, hasNotch: Bool, scale: CGFloat = 1, expandedCornerRadius: CGFloat = 32) {
        self.notchSize = CGSize(width: max(80, notchSize.width), height: max(18, notchSize.height))
        self.hasNotch = hasNotch
        self.scale = min(1.4, max(0.7, scale.isFinite ? scale : 1))
        self.expandedCornerRadius = min(48, max(8, expandedCornerRadius))
    }

    public var compactHeight: CGFloat { notchSize.height }
    public var bubbleDiameter: CGFloat { compactHeight }
    public var bubbleSpacing: CGFloat { 6 }

    public func wingWidth(_ style: CompactStyle) -> CGFloat {
        switch style {
        case .standard: (compactHeight + 32) * scale
        case .wide: (compactHeight + 70) * scale
        }
    }

    public var expandedWidth: CGFloat { max(notchSize.width + 160, 440 * scale) }
    public var searchWidth: CGFloat { max(notchSize.width + 220, 580 * scale) }
    public var searchMaxHeight: CGFloat { 440 * scale }

    public func expandedHeight(_ style: ExpandedStyle) -> CGFloat {
        let content: CGFloat = switch style {
        case .home: 112
        case .media: 140
        case .timer: 112
        case .download: 112
        case .event: 84
        case .research: 300
        }
        return compactHeight + content * scale
    }

    /// Size of the main island shape for a given state.
    public func size(mode: IslandMode, compact: CompactStyle, expanded: ExpandedStyle, searchHeight: CGFloat = 0) -> CGSize {
        switch mode {
        case .idle:
            // Hidden inside the notch. On notch-less displays it collapses to nothing at the top edge.
            return hasNotch ? notchSize : CGSize(width: notchSize.width * 0.6, height: 0)
        case .compact:
            return CGSize(width: notchSize.width + 2 * wingWidth(compact), height: compactHeight)
        case .expanded:
            return CGSize(width: expandedWidth, height: expandedHeight(expanded))
        case .search:
            let h = min(searchMaxHeight, max(compactHeight + 52 * scale, searchHeight))
            return CGSize(width: searchWidth, height: h)
        }
    }

    public func bottomCornerRadius(mode: IslandMode, height: CGFloat) -> CGFloat {
        switch mode {
        case .idle, .compact: min(height / 2, max(8, compactHeight * 0.38))
        case .expanded, .search: min(height / 2, expandedCornerRadius * scale)
        }
    }

    public func topEarRadius(mode: IslandMode) -> CGFloat {
        switch mode {
        case .idle, .compact: 6
        case .expanded, .search: 12
        }
    }

    /// Fixed window size large enough for every state (window never resizes during animation).
    public var windowSize: CGSize {
        let compactWide = notchSize.width + 2 * wingWidth(.wide) + 2 * (bubbleDiameter + bubbleSpacing) + 16
        let w = max(searchWidth, expandedWidth, compactWide) + 80
        let h = max(searchMaxHeight, expandedHeight(.research)) + 40
        return CGSize(width: ceil(w), height: ceil(h))
    }

    /// Interactive region (relative to the top-centre anchor, y growing downward) for mouse hit-testing.
    public func hitRect(islandSize: CGSize, bubbles: Int, mode: IslandMode) -> CGRect {
        var rect = CGRect(x: -islandSize.width / 2, y: 0, width: islandSize.width, height: max(islandSize.height, 1))
        if mode == .compact, bubbles > 0 {
            rect.size.width += CGFloat(bubbles) * (bubbleDiameter + bubbleSpacing)
        }
        if mode == .idle {
            // Hover hot-zone so the Island can be revealed even when empty.
            rect = CGRect(x: -notchSize.width / 2, y: 0, width: notchSize.width, height: compactHeight)
        }
        return rect.insetBy(dx: -4, dy: 0).union(CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height + 4))
    }
}

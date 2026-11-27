import CoreGraphics
import Foundation

/// One on-screen window as reported by `CGWindowListCopyWindowInfo` (only the fields we need).
public struct WindowInfo: Equatable, Sendable {
    public var ownerPID: Int32
    public var layer: Int
    /// Quartz global coordinates: origin at the top-left of the primary display, y grows downward.
    public var bounds: CGRect

    public init(ownerPID: Int32, layer: Int, bounds: CGRect) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.bounds = bounds
    }

    /// Parses one entry of `CGWindowListCopyWindowInfo`; nil when a required field is missing.
    public init?(_ dictionary: [String: Any]) {
        guard let pid = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue,
              let boundsDict = dictionary[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { return nil }
        self.init(ownerPID: pid, layer: layer, bounds: bounds)
    }
}

/// Decides whether the frontmost app is showing a full-screen window on a given display.
/// A full-screen window is an ordinary (layer 0) window covering the whole screen, menu-bar area included.
public enum FullScreenDetector {
    /// Allowed rounding difference between a window's bounds and the screen frame, in points.
    public static let tolerance: CGFloat = 1

    public static func isFullScreen(windows: [WindowInfo], screenFrame: CGRect, frontmostPID: Int32?) -> Bool {
        guard let frontmostPID, !screenFrame.isEmpty else { return false }
        return windows.contains { w in
            w.ownerPID == frontmostPID && w.layer == 0 && approximatelyEqual(w.bounds, screenFrame)
        }
    }

    /// Converts an AppKit global frame (origin bottom-left of the primary display, y up) to Quartz global
    /// coordinates (origin top-left of the primary display, y down). `primaryHeight` is the primary
    /// display's frame height (the screen whose AppKit origin is 0,0).
    public static func quartzFrame(fromAppKit frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    static func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}

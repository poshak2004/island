import CoreGraphics
import Foundation
@testable import IslandCore

@MainActor
func registerFullScreenTests() {
    let S = "FullScreen"
    let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)

    test(S, "frontmost app with a screen-sized layer-0 window is full screen") {
        let w = [WindowInfo(ownerPID: 42, layer: 0, bounds: screen)]
        expect(FullScreenDetector.isFullScreen(windows: w, screenFrame: screen, frontmostPID: 42))
    }

    test(S, "another app's full-screen window does not count") {
        let w = [WindowInfo(ownerPID: 7, layer: 0, bounds: screen)]
        expect(!FullScreenDetector.isFullScreen(windows: w, screenFrame: screen, frontmostPID: 42))
    }

    test(S, "maximised window below the menu bar is not full screen") {
        let w = [WindowInfo(ownerPID: 42, layer: 0, bounds: CGRect(x: 0, y: 33, width: 1470, height: 923))]
        expect(!FullScreenDetector.isFullScreen(windows: w, screenFrame: screen, frontmostPID: 42))
    }

    test(S, "non-zero layers (menu bar, overlays) are ignored") {
        let w = [WindowInfo(ownerPID: 42, layer: 25, bounds: screen)]
        expect(!FullScreenDetector.isFullScreen(windows: w, screenFrame: screen, frontmostPID: 42))
    }

    test(S, "no frontmost app or empty screen is never full screen") {
        let w = [WindowInfo(ownerPID: 42, layer: 0, bounds: screen)]
        expect(!FullScreenDetector.isFullScreen(windows: w, screenFrame: screen, frontmostPID: nil))
        expect(!FullScreenDetector.isFullScreen(windows: w, screenFrame: .zero, frontmostPID: 42))
    }

    test(S, "sub-point rounding still matches") {
        let w = [WindowInfo(ownerPID: 42, layer: 0, bounds: CGRect(x: 0.5, y: 0, width: 1469.5, height: 956))]
        expect(FullScreenDetector.isFullScreen(windows: w, screenFrame: screen, frontmostPID: 42))
    }

    test(S, "full-screen window on another display does not count") {
        let external = CGRect(x: 1470, y: -484, width: 2560, height: 1440)
        let w = [WindowInfo(ownerPID: 42, layer: 0, bounds: external)]
        expect(!FullScreenDetector.isFullScreen(windows: w, screenFrame: screen, frontmostPID: 42))
        expect(FullScreenDetector.isFullScreen(windows: w, screenFrame: external, frontmostPID: 42))
    }

    test(S, "AppKit frame converts to Quartz top-left coordinates") {
        expectEqual(FullScreenDetector.quartzFrame(fromAppKit: screen, primaryHeight: 956), screen)
        // External display to the right, bottom-aligned with a 956pt-tall primary.
        let ext = CGRect(x: 1470, y: 0, width: 2560, height: 1440)
        expectEqual(FullScreenDetector.quartzFrame(fromAppKit: ext, primaryHeight: 956),
                    CGRect(x: 1470, y: -484, width: 2560, height: 1440))
        // Display stacked above the primary.
        let above = CGRect(x: 0, y: 956, width: 1920, height: 1080)
        expectEqual(FullScreenDetector.quartzFrame(fromAppKit: above, primaryHeight: 956),
                    CGRect(x: 0, y: -1080, width: 1920, height: 1080))
    }

    test(S, "parses CGWindowList dictionaries") {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 50).dictionaryRepresentation
        let d: [String: Any] = [kCGWindowOwnerPID as String: NSNumber(value: 9), kCGWindowLayer as String: NSNumber(value: 0),
                                kCGWindowBounds as String: bounds]
        expectEqual(WindowInfo(d), WindowInfo(ownerPID: 9, layer: 0, bounds: CGRect(x: 0, y: 0, width: 100, height: 50)))
        expect(WindowInfo([kCGWindowOwnerPID as String: NSNumber(value: 9)]) == nil)
    }
}

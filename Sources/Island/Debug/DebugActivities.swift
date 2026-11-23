import Foundation
import IslandCore

/// Synthetic activities for the debug panel and self-test. They go through ActivityManager exactly
/// like real providers, so they exercise the real pipeline.
enum DebugActivities {
    static func music(playing: Bool = true, source: String = "com.apple.Music", name: String = "Music") -> Activity {
        Activity(id: "media", kind: .media, priority: playing ? .normal : .low, content: .media(MediaActivity(
            sourceBundleID: source, sourceName: name, title: "Midnight City", artist: "M83",
            album: "Hurry Up, We're Dreaming", artworkID: "debug-\(source)", playbackState: playing ? .playing : .paused,
            elapsed: 42, positionTimestamp: Date(), duration: 243, controls: [.playPause, .next, .previous])))
    }

    static func download(fraction: Double = 0.42) -> Activity {
        Activity(id: "download.debug", kind: .download, priority: .low, content: .download(DownloadActivity(
            filename: "Xcode_27.xip", fraction: fraction, completedBytes: Int64(fraction * 3_200_000_000),
            totalBytes: 3_200_000_000, bytesPerSecond: 24_500_000, estimatedTimeRemaining: 74, state: .active, isCancellable: true)))
    }

    static func recording() -> Activity {
        Activity(id: "recording", kind: .recording, priority: .normal,
                 content: .recording(RecordingActivity(microphone: true, camera: false, startedAt: Date().addingTimeInterval(-151))))
    }

    static func criticalEvent() -> Activity {
        Activity(id: "event.critical", kind: .call, priority: .critical, content: .event(SystemEventActivity(
            symbol: "phone.fill", title: "Test critical event", subtitle: "Critical activities take over immediately", tintHex: "#34C759")),
                 expiresAt: Date().addingTimeInterval(8))
    }

    static func battery(level: Int = 84, charging: Bool = true) -> Activity {
        Activity(id: "battery", kind: .battery, priority: .high,
                 content: .battery(BatteryActivity(level: level, isCharging: charging, reason: charging ? .pluggedIn : .low)),
                 expiresAt: Date().addingTimeInterval(4))
    }

    static let sampleScript = """
    Hi everyone, and thanks for joining. Today I want to show you Island, a Dynamic Island for the Mac notch.

    It lives right where your camera is, so when you read this script you are looking straight at the people watching you.

    The text scrolls at your speed. Hover to pause, press Escape to tuck it away, and click the notch to bring it back.
    """
}

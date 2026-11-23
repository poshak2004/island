import Foundation

public enum MediaCommand: Equatable, Sendable {
    case togglePlayPause, play, pause, next, previous
    case seek(to: TimeInterval)
}

public enum TimerCommand: Equatable, Sendable {
    case start(duration: TimeInterval, label: String)
    case pause(UUID), resume(UUID), reset(UUID), stop(UUID)
}

public enum DownloadCommand: Equatable, Sendable {
    case cancel(id: String), pause(id: String), resume(id: String)
    case reveal(URL), open(URL)
}

public enum TeleprompterCommand: Equatable, Sendable {
    case start(text: String, title: String)
    case togglePlayPause, restart, stop
    case faster, slower
    case skip(lines: Int)
    case toggleVoiceFollow
    case pointerInside(Bool)
}

public enum ShelfCommand: Equatable, Sendable {
    case add([URL])
    /// Show the shelf (its drop targets when empty) without waiting for a drag.
    case reveal
    case remove(UUID)
    case clear
    /// AirDrop the given files (dropped straight onto the AirDrop target) or, when empty, the whole shelf.
    case airDrop([URL])
}

public enum IslandUICommand: Equatable, Sendable {
    case expand, collapse, toggleSearch, presentTransient(seconds: TimeInterval)
    case select(activityID: String?), selectNext, dismiss(activityID: String)
}

/// Every user-visible action flows through one typed command. Views and AI never call services directly.
public enum IslandCommand: Equatable, Sendable {
    case media(MediaCommand, sourceBundleID: String?)
    case timer(TimerCommand)
    case download(DownloadCommand)
    case teleprompter(TeleprompterCommand)
    case shelf(ShelfCommand)
    case ui(IslandUICommand)
    case openURL(URL)
    case revealFile(URL)
    case openFile(URL)
    case launchApplication(URL)
    /// Runs one of your Shortcuts (Shortcuts app) by name.
    case runShortcut(name: String)
    case action(AppAction)
    case openSettings

    public var safety: SafetyLevel {
        switch self {
        case .action(let a): a.safety
        // A Shortcut can do anything, so only a direct click or keypress may run it, never AI or a rule.
        case .runShortcut: .confirm
        default: .safe
        }
    }
}

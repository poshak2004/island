import Foundation

/// Apps known to take ⌥Space by default. They can grab it without macOS reporting a conflict, so
/// Island names them when they're running and the search shortcut is still ⌥Space.
public enum ShortcutConflicts {
    static let optionSpaceOwners: [(bundleID: String, name: String)] = [
        ("com.raycast.macos", "Raycast"),
        ("com.runningwithcrayons.Alfred", "Alfred"),
        ("com.openai.chat", "ChatGPT"),
    ]

    public static func likelyOwners(of shortcut: IslandShortcut, running: Set<String>) -> [String] {
        guard shortcut.keyCode == IslandShortcut.defaultSearch.keyCode,
              shortcut.carbonModifiers == IslandShortcut.defaultSearch.carbonModifiers else { return [] }
        return optionSpaceOwners.filter { running.contains($0.bundleID) }.map(\.name)
    }
}

import AppKit
import IslandCore

/// Speaks new Island events to VoiceOver. The Island's panel is never key, so without this a VoiceOver
/// user wouldn't learn that a timer finished or AirPods connected (HIG › Accessibility › Vision).
@MainActor
enum Announcer {
    static func announce(_ activity: Activity) {
        guard activity.kind.announcesArrival, NSWorkspace.shared.isVoiceOverEnabled else { return }
        let text = ActivityPresentation.accessibilityLabel(for: activity)
        guard !text.isEmpty else { return }
        let priority: NSAccessibilityPriorityLevel = activity.priority >= .high ? .high : .medium
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: priority.rawValue])
    }
}

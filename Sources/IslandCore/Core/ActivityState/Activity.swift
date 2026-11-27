import Foundation

/// Deterministic priority. Higher wins. `critical` may interrupt anything; `low` never interrupts.
public enum ActivityPriority: Int, Comparable, CaseIterable, Codable, Sendable, CustomStringConvertible {
    case low = 0, normal = 1, high = 2, critical = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { ["low", "normal", "high", "critical"][rawValue] }
}

public enum ActivityKind: String, CaseIterable, Codable, Sendable, Hashable {
    case media, timer, download, recording, call, battery, network, device, calendar, clipboard, search, notification, custom
    case teleprompter, shelf

    /// Whether VoiceOver should announce a new activity of this kind. Things that come and go on their
    /// own (track changes, clipboard confirmations, search) would only be chatter.
    public var announcesArrival: Bool {
        switch self {
        case .media, .clipboard, .search: false
        default: true
        }
    }

    public var displayName: String {
        switch self {
        case .media: "Media"
        case .timer: "Timers"
        case .download: "Downloads"
        case .recording: "Microphone & Camera"
        case .call: "Calls"
        case .battery: "Battery"
        case .network: "Network"
        case .device: "Devices"
        case .calendar: "Calendar"
        case .clipboard: "Clipboard"
        case .search: "Search"
        case .notification: "System Events"
        case .custom: "Custom"
        case .teleprompter: "Teleprompter"
        case .shelf: "File Shelf"
        }
    }
}

/// A single live activity rendered by the Island. Providers create these; only `ActivityManager` stores them.
public struct Activity: Identifiable, Equatable, Sendable {
    public let id: String
    public var kind: ActivityKind
    public var priority: ActivityPriority
    public var content: ActivityContent
    /// Transient activities disappear automatically at this moment.
    public var expiresAt: Date?
    /// Set by the manager: arrival order, preserved across updates. Used for deterministic tie-breaking.
    public internal(set) var sequence: UInt64 = 0
    public internal(set) var createdAt: Date = .distantPast
    public internal(set) var updatedAt: Date = .distantPast

    public init(id: String, kind: ActivityKind, priority: ActivityPriority, content: ActivityContent, expiresAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.priority = priority
        self.content = content
        self.expiresAt = expiresAt
    }

    public var isTransient: Bool { expiresAt != nil }
}

/// The single entry point by which providers talk to the Island.
public enum ActivityUpdate: Sendable {
    case upsert(Activity)
    case remove(id: String)
    /// Marks an activity complete: it is replaced by `final` (if any) for `linger` seconds, then removed.
    case complete(id: String, final: Activity?, linger: TimeInterval)
}

extension ActivityUpdate {
    /// Quiet mode: a new arrival may appear but not take over — `.high` becomes `.normal`. Critical
    /// alerts are unchanged, so anything that truly needs attention still gets it.
    /// Quiets only the arrivals whose kind the user set to Quiet.
    public func quieted(when isQuiet: (ActivityKind) -> Bool) -> ActivityUpdate {
        guard case .upsert(let a) = self, isQuiet(a.kind) else { return self }
        return quieted()
    }

    public func quieted() -> ActivityUpdate {
        guard case .upsert(var a) = self, a.priority == .high else { return self }
        a.priority = .normal
        return .upsert(a)
    }
}

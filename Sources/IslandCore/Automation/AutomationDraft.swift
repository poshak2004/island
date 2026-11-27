import Foundation

/// Editable, validated form state for one rule. The editor works on one trigger, at most one condition and
/// one action; extra conditions/actions on an existing rule are carried through unchanged.
public struct AutomationDraft: Equatable, Sendable {
    public enum TriggerKind: String, CaseIterable, Identifiable, Sendable {
        case battery, download, timer, media, networkConnected, networkDisconnected, device
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .battery: "Battery drops below a level"
            case .download: "A download finishes"
            case .timer: "A timer finishes"
            case .media: "Music or video starts playing"
            case .networkConnected: "The network connects"
            case .networkDisconnected: "The network disconnects"
            case .device: "AirPods or headphones connect"
            }
        }
    }

    public enum ConditionKind: String, CaseIterable, Identifiable, Sendable {
        case none, hours, activityActive, activityInactive
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .none: "Always"
            case .hours: "Only between certain hours"
            case .activityActive: "Only while an activity is in the Island"
            case .activityInactive: "Only while an activity is not in the Island"
            }
        }
    }

    public enum ActionKind: String, CaseIterable, Identifiable, Sendable {
        case presentIsland, showMessage, playSound, openURL, openApp
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .presentIsland: "Open the Island"
            case .showMessage: "Show a message"
            case .playSound: "Play a sound"
            case .openURL: "Open a web page"
            case .openApp: "Open an app"
            }
        }
    }

    public enum Field: Hashable, Sendable { case name, batteryPercent, hours, seconds, message, sound, url, app }

    public static let sounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
                                "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
    public static let secondsRange: ClosedRange<Double> = 1...60
    public static let batteryRange: ClosedRange<Int> = 1...99
    public static let messageLimit = 80
    static let defaultSymbol = "bell.fill"

    public var id: UUID?
    public var name = ""
    public var enabled = true
    public var trigger: TriggerKind = .device
    public var batteryPercent = 20
    public var condition: ConditionKind = .none
    public var startHour = 22
    public var endHour = 7
    public var activityKind: ActivityKind = .call
    public var action: ActionKind = .presentIsland
    public var seconds = "3"
    public var message = ""
    public var symbol = AutomationDraft.defaultSymbol
    public var sound = "Glass"
    public var url = ""
    public var app = ""
    var extraConditions: [AutomationRule.Condition] = []
    var extraActions: [AutomationRule.Action] = []

    public init() {}
}

// MARK: Validation and building

extension AutomationDraft {
    /// Inline error messages keyed by field; only fields the current choices use are checked.
    public var errors: [Field: String] {
        var e: [Field: String] = [:]
        if trimmed(name).isEmpty { e[.name] = "Give the rule a name." }
        if trigger == .battery, !Self.batteryRange.contains(batteryPercent) { e[.batteryPercent] = "Choose a level from 1% to 99%." }
        if condition == .hours, !(0...23).contains(startHour) || !(0...23).contains(endHour) || startHour == endHour {
            e[.hours] = "Choose two different hours."
        }
        if let message = actionError { e[actionField] = message }
        return e
    }

    public var isValid: Bool { errors.isEmpty }

    /// The rule this draft describes, or nil while any field is invalid.
    public func build() -> AutomationRule? {
        guard isValid, let action = builtAction else { return nil }
        let conditions = (builtCondition.map { [$0] } ?? []) + extraConditions
        return AutomationRule(id: id ?? UUID(), name: trimmed(name), enabled: enabled, trigger: builtTrigger,
                              conditions: conditions, actions: [action] + extraActions)
    }

    private var actionField: Field {
        switch action {
        case .presentIsland: .seconds
        case .showMessage: .message
        case .playSound: .sound
        case .openURL: .url
        case .openApp: .app
        }
    }

    private var actionError: String? {
        switch action {
        case .presentIsland: parsedSeconds == nil ? "Enter a number of seconds from 1 to 60." : nil
        case .showMessage: messageError
        case .playSound: Self.sounds.contains(sound) ? nil : "Choose a sound."
        case .openURL: parsedURL == nil ? "Enter a web address that starts with http:// or https://." : nil
        case .openApp: trimmed(app).isEmpty ? "Enter the name of an app." : nil
        }
    }

    private var messageError: String? {
        let text = trimmed(message)
        if text.isEmpty { return "Enter a message to show." }
        return text.count > Self.messageLimit ? "Keep the message under \(Self.messageLimit) characters." : nil
    }

    var parsedSeconds: Double? {
        guard let value = Double(trimmed(seconds)), Self.secondsRange.contains(value) else { return nil }
        return value
    }

    var parsedURL: URL? {
        guard let url = URL(string: trimmed(url)), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    private var builtTrigger: AutomationRule.Trigger {
        switch trigger {
        case .battery: .batteryBelow(percent: batteryPercent)
        case .download: .downloadCompleted
        case .timer: .timerFinished
        case .media: .mediaStarted
        case .networkConnected: .networkChanged(connected: true)
        case .networkDisconnected: .networkChanged(connected: false)
        case .device: .deviceConnected
        }
    }

    private var builtCondition: AutomationRule.Condition? {
        switch condition {
        case .none: nil
        case .hours: .hourBetween(start: startHour, end: endHour)
        case .activityActive: .activityActive(activityKind)
        case .activityInactive: .activityInactive(activityKind)
        }
    }

    private var builtAction: AutomationRule.Action? {
        switch action {
        case .presentIsland: parsedSeconds.map { .presentIsland(seconds: $0) }
        case .showMessage: .showEvent(symbol: symbol, title: trimmed(message))
        case .playSound: .playSound(name: sound)
        case .openURL: parsedURL.map { .openURL($0) }
        case .openApp: .openApp(name: trimmed(app))
        }
    }

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: Loading an existing rule

extension AutomationDraft {
    public init(rule: AutomationRule) {
        self.init()
        id = rule.id
        name = rule.name
        enabled = rule.enabled
        apply(rule.trigger)
        if let first = rule.conditions.first { apply(first) }
        extraConditions = Array(rule.conditions.dropFirst())
        if let first = rule.actions.first { apply(first) }
        extraActions = Array(rule.actions.dropFirst())
    }

    private mutating func apply(_ t: AutomationRule.Trigger) {
        switch t {
        case .batteryBelow(let p): trigger = .battery; batteryPercent = p
        case .downloadCompleted: trigger = .download
        case .timerFinished: trigger = .timer
        case .mediaStarted: trigger = .media
        case .networkChanged(let connected): trigger = connected ? .networkConnected : .networkDisconnected
        case .deviceConnected: trigger = .device
        }
    }

    private mutating func apply(_ c: AutomationRule.Condition) {
        switch c {
        case .hourBetween(let s, let e): condition = .hours; startHour = s; endHour = e
        case .activityActive(let k): condition = .activityActive; activityKind = k
        case .activityInactive(let k): condition = .activityInactive; activityKind = k
        }
    }

    private mutating func apply(_ a: AutomationRule.Action) {
        switch a {
        case .presentIsland(let s): action = .presentIsland; seconds = AutomationFormat.number(s)
        case .showEvent(let sym, let title): action = .showMessage; symbol = sym; message = title
        case .playSound(let n): action = .playSound; sound = n
        case .openURL(let u): action = .openURL; url = u.absoluteString
        case .openApp(let n): action = .openApp; app = n
        }
    }
}

// MARK: List operations (return new arrays; never mutate in place)

extension Array where Element == AutomationRule {
    /// Replaces the rule with the same id, or appends it.
    public func upserting(_ rule: AutomationRule) -> [AutomationRule] {
        guard contains(where: { $0.id == rule.id }) else { return self + [rule] }
        return map { $0.id == rule.id ? rule : $0 }
    }

    public func removing(id: UUID) -> [AutomationRule] { filter { $0.id != id } }

    public func setting(enabled: Bool, for id: UUID) -> [AutomationRule] {
        map { rule in
            guard rule.id == id else { return rule }
            var copy = rule
            copy.enabled = enabled
            return copy
        }
    }

    /// Moves the rule by `offset` places (negative is up), clamped to the list bounds.
    public func moving(id: UUID, by offset: Int) -> [AutomationRule] {
        guard let from = firstIndex(where: { $0.id == id }) else { return self }
        let to = Swift.min(Swift.max(from + offset, 0), count - 1)
        guard to != from else { return self }
        var copy = self
        let rule = copy.remove(at: from)
        copy.insert(rule, at: to)
        return copy
    }
}

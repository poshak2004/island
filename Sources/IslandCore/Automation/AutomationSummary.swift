import Foundation

/// Plain-English descriptions of rules, e.g. "When AirPods or headphones connect → Open the Island for 3 s".
/// Hours are formatted on a fixed 12-hour clock so summaries are stable regardless of locale.
extension AutomationRule {
    public var summary: String {
        let when = ([trigger.summary] + conditions.map(\.summary)).joined(separator: ", ")
        let then = actions.isEmpty ? "Do nothing" : actions.map(\.summary).joined(separator: ", then ")
        return "\(when) → \(then)"
    }
}

extension AutomationRule.Trigger {
    public var summary: String {
        switch self {
        case .batteryBelow(let percent): "When battery drops below \(percent)%"
        case .downloadCompleted: "When a download finishes"
        case .timerFinished: "When a timer finishes"
        case .mediaStarted: "When music or video starts playing"
        case .networkChanged(let connected): connected ? "When the network connects" : "When the network disconnects"
        case .deviceConnected: "When AirPods or headphones connect"
        }
    }
}

extension AutomationRule.Condition {
    public var summary: String {
        switch self {
        case .hourBetween(let start, let end):
            "only between \(AutomationFormat.hour(start)) and \(AutomationFormat.hour(end))"
        case .activityActive(let kind): "only while \(kind.displayName) is in the Island"
        case .activityInactive(let kind): "only while \(kind.displayName) is not in the Island"
        }
    }
}

extension AutomationRule.Action {
    public var summary: String {
        switch self {
        case .presentIsland(let seconds): "Open the Island for \(AutomationFormat.seconds(seconds))"
        case .showEvent(_, let title): "Show “\(title)”"
        case .playSound(let name): "Play the “\(name)” sound"
        case .openURL(let url): "Open \(url.host ?? url.absoluteString)"
        case .openApp(let name): "Open \(name)"
        }
    }
}

public enum AutomationFormat {
    /// 0 → "12 AM", 7 → "7 AM", 12 → "12 PM", 22 → "10 PM". Out-of-range values wrap into 0–23.
    public static func hour(_ h: Int) -> String {
        let hour = ((h % 24) + 24) % 24
        let suffix = hour < 12 ? "AM" : "PM"
        let display = hour % 12 == 0 ? 12 : hour % 12
        return "\(display) \(suffix)"
    }

    /// 3 → "3 s", 4.5 → "4.5 s".
    public static func seconds(_ s: Double) -> String { "\(number(s)) s" }

    /// 3 → "3", 4.5 → "4.5" (one decimal place at most).
    public static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}

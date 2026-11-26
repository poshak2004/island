import Foundation
import IslandCore

@MainActor
func registerAutomationTests() {
    registerAutomationSummaryTests()
    registerAutomationDraftTests()
    registerAutomationListTests()
}

@MainActor
private func registerAutomationSummaryTests() {
    let S = "AutomationSummary"

    test(S, "trigger and single action read as plain English") {
        let rule = AutomationRule(name: "AirPods", trigger: .deviceConnected, actions: [.presentIsland(seconds: 3)])
        expectEqual(rule.summary, "When AirPods or headphones connect → Open the Island for 3 s")
    }

    test(S, "conditions and multiple actions are joined") {
        let rule = AutomationRule(name: "x", trigger: .batteryBelow(percent: 15), conditions: [.hourBetween(start: 22, end: 7)],
                                  actions: [.showEvent(symbol: "bolt", title: "Charge"), .playSound(name: "Glass")])
        expectEqual(rule.summary, "When battery drops below 15%, only between 10 PM and 7 AM → Show “Charge”, then Play the “Glass” sound")
    }

    test(S, "every trigger, condition and action has a summary") {
        expectEqual(AutomationRule.Trigger.networkChanged(connected: false).summary, "When the network disconnects")
        expectEqual(AutomationRule.Trigger.timerFinished.summary, "When a timer finishes")
        expectEqual(AutomationRule.Condition.activityActive(.call).summary, "only while Calls is in the Island")
        expectEqual(AutomationRule.Condition.activityInactive(.media).summary, "only while Media is not in the Island")
        expectEqual(AutomationRule.Action.openApp(name: "Music").summary, "Open Music")
        expectEqual(AutomationRule.Action.openURL(URL(string: "https://example.com/a")!).summary, "Open example.com")
        expectEqual(AutomationRule.Action.presentIsland(seconds: 4.5).summary, "Open the Island for 4.5 s")
        expectEqual(AutomationRule(name: "n", trigger: .mediaStarted, actions: []).summary, "When music or video starts playing → Do nothing")
    }

    test(S, "hour formatting is 12-hour and wraps") {
        expectEqual(AutomationFormat.hour(0), "12 AM")
        expectEqual(AutomationFormat.hour(7), "7 AM")
        expectEqual(AutomationFormat.hour(12), "12 PM")
        expectEqual(AutomationFormat.hour(23), "11 PM")
        expectEqual(AutomationFormat.hour(25), "1 AM")
        expectEqual(AutomationFormat.number(3.0), "3")
        expectEqual(AutomationFormat.number(2.25), "2.3")
    }

    test(S, "decoding tolerates missing enabled and conditions") {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Old","trigger":{"downloadCompleted":{}},"actions":[{"presentIsland":{"seconds":3}}]}]"#
        let rules = try JSONDecoder().decode([AutomationRule].self, from: Data(json.utf8))
        expectEqual(rules.count, 1)
        expectEqual(rules.first?.enabled, true)
        expectEqual(rules.first?.conditions, [])
        let roundTrip = try JSONDecoder().decode([AutomationRule].self, from: JSONEncoder().encode(rules))
        expectEqual(roundTrip, rules)
    }

    test(S, "new actions round-trip and disabled rules are skipped") {
        let url = URL(string: "https://example.com")!
        var rule = AutomationRule(name: "o", trigger: .timerFinished, actions: [.openURL(url), .openApp(name: "Notes")])
        let decoded = try JSONDecoder().decode(AutomationRule.self, from: JSONEncoder().encode(rule))
        expectEqual(decoded, rule)
        var st: [UUID: Bool] = [:]
        let ctx = AutomationContext(activeKinds: [])
        expectEqual(AutomationEngine.evaluate([rule], event: .timerFinished(label: "t"), context: ctx, state: &st), [.openURL(url), .openApp(name: "Notes")])
        rule.enabled = false
        expectEqual(AutomationEngine.evaluate([rule], event: .timerFinished(label: "t"), context: ctx, state: &st).count, 0)
    }
}

@MainActor
private func registerAutomationDraftTests() {
    let D = "AutomationDraft"

    test(D, "a fresh draft needs a name") {
        var draft = AutomationDraft()
        expect(draft.errors[.name] != nil)
        expect(draft.build() == nil)
        draft.name = "  "
        expect(draft.errors[.name] != nil)
        draft.name = " Ping "
        expect(draft.isValid)
        expectEqual(draft.build()?.name, "Ping")
    }

    test(D, "seconds must be a number from 1 to 60") {
        var draft = AutomationDraft()
        draft.name = "n"
        for bad in ["", "abc", "0", "0.5", "61"] {
            draft.seconds = bad
            expect(draft.errors[.seconds] != nil, "\(bad) should be invalid")
        }
        for good in ["1", "4.5", "60"] {
            draft.seconds = good
            expect(draft.errors[.seconds] == nil, "\(good) should be valid")
        }
        expectEqual(draft.build()?.actions, [.presentIsland(seconds: 60)])
    }

    test(D, "URLs must be http or https with a host") {
        var draft = AutomationDraft()
        draft.name = "n"
        draft.action = .openURL
        for bad in ["", "example.com", "ftp://example.com", "file:///etc/hosts", "javascript:alert(1)", "https://"] {
            draft.url = bad
            expect(draft.errors[.url] != nil, "\(bad) should be invalid")
        }
        draft.url = " https://example.com/x "
        expect(draft.isValid)
        expectEqual(draft.build()?.actions, [.openURL(URL(string: "https://example.com/x")!)])
    }

    test(D, "message, app, sound and hours are validated") {
        var draft = AutomationDraft()
        draft.name = "n"
        draft.action = .showMessage
        expect(draft.errors[.message] != nil)
        draft.message = String(repeating: "a", count: AutomationDraft.messageLimit + 1)
        expect(draft.errors[.message] != nil)
        draft.action = .openApp
        expect(draft.errors[.app] != nil)
        draft.action = .playSound
        draft.sound = "Nope"
        expect(draft.errors[.sound] != nil)
        draft.sound = "Glass"
        draft.condition = .hours
        draft.startHour = 9; draft.endHour = 9
        expect(draft.errors[.hours] != nil)
        draft.endHour = 17
        expect(draft.isValid)
        expectEqual(draft.build()?.conditions, [.hourBetween(start: 9, end: 17)])
    }

    test(D, "only the chosen action's field is checked") {
        var draft = AutomationDraft()
        draft.name = "n"
        draft.url = "not a url"
        draft.seconds = "5"
        expect(draft.isValid)
    }

    test(D, "editing a rule round-trips and keeps extra conditions and actions") {
        let rule = AutomationRule(name: "Low", enabled: false, trigger: .batteryBelow(percent: 15),
                                  conditions: [.activityInactive(.call), .hourBetween(start: 8, end: 20)],
                                  actions: [.presentIsland(seconds: 4.5), .playSound(name: "Ping")])
        let draft = AutomationDraft(rule: rule)
        expectEqual(draft.trigger, .battery)
        expectEqual(draft.batteryPercent, 15)
        expectEqual(draft.condition, .activityInactive)
        expectEqual(draft.seconds, "4.5")
        expectEqual(draft.build(), rule)
    }

    test(D, "every trigger kind builds the matching trigger") {
        var draft = AutomationDraft()
        draft.name = "n"
        let expected: [AutomationDraft.TriggerKind: AutomationRule.Trigger] = [
            .battery: .batteryBelow(percent: 20), .download: .downloadCompleted, .timer: .timerFinished, .media: .mediaStarted,
            .networkConnected: .networkChanged(connected: true), .networkDisconnected: .networkChanged(connected: false),
            .device: .deviceConnected,
        ]
        for kind in AutomationDraft.TriggerKind.allCases {
            draft.trigger = kind
            expectEqual(draft.build()?.trigger, expected[kind])
            expectEqual(AutomationDraft(rule: draft.build() ?? AutomationRule.defaults[0]).trigger, kind)
        }
    }
}

@MainActor
private func registerAutomationListTests() {
    let L = "AutomationList"
    let a = AutomationRule(name: "a", trigger: .timerFinished, actions: [])
    let b = AutomationRule(name: "b", trigger: .mediaStarted, actions: [])
    let c = AutomationRule(name: "c", trigger: .deviceConnected, actions: [])

    test(L, "upsert replaces by id or appends") {
        var renamed = b
        renamed.name = "B"
        expectEqual([a, b].upserting(renamed).map(\.name), ["a", "B"])
        expectEqual([a, b].upserting(c).map(\.name), ["a", "b", "c"])
    }

    test(L, "remove and toggle leave the original untouched") {
        let original = [a, b, c]
        expectEqual(original.removing(id: b.id).map(\.name), ["a", "c"])
        expectEqual(original.setting(enabled: false, for: c.id).map(\.enabled), [true, true, false])
        expectEqual(original.map(\.enabled), [true, true, true])
    }

    test(L, "move clamps to the ends") {
        let list = [a, b, c]
        expectEqual(list.moving(id: c.id, by: -1).map(\.name), ["a", "c", "b"])
        expectEqual(list.moving(id: a.id, by: 1).map(\.name), ["b", "a", "c"])
        expectEqual(list.moving(id: a.id, by: -1).map(\.name), ["a", "b", "c"])
        expectEqual(list.moving(id: b.id, by: 5).map(\.name), ["a", "c", "b"])
        expectEqual(list.moving(id: UUID(), by: 1).map(\.name), ["a", "b", "c"])
    }
}

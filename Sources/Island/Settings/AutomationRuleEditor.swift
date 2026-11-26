import IslandCore
import SwiftUI

/// Sheet for creating or editing one automation rule: When (trigger), Only If (optional condition), Then (action).
/// Errors appear inline after the first Save attempt and update as you type.
struct AutomationRuleEditor: View {
    @State var draft: AutomationDraft
    let isNew: Bool
    let onSave: (AutomationRule) -> Void
    let onCancel: () -> Void
    @State private var showErrors = false

    private static let activityKinds = ActivityKind.allCases.filter { $0 != .search && $0 != .custom }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                nameSection
                triggerSection
                conditionSection
                actionSection
            }
            .formStyle(.grouped)
            buttons
        }
        .frame(width: 480, height: 520)
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            TextField("Name", text: $draft.name, prompt: Text("Battery low warning"))
            error(.name)
            Toggle("Enabled", isOn: $draft.enabled)
        }
    }

    private var triggerSection: some View {
        Section("When") {
            Picker("Event", selection: $draft.trigger) {
                ForEach(AutomationDraft.TriggerKind.allCases) { Text($0.title).tag($0) }
            }
            if draft.trigger == .battery {
                Stepper(value: $draft.batteryPercent, in: AutomationDraft.batteryRange, step: 5) {
                    LabeledContent("Battery level", value: "\(draft.batteryPercent)%")
                }
                error(.batteryPercent)
            }
        }
    }

    private var conditionSection: some View {
        Section("Only If") {
            Picker("Condition", selection: $draft.condition) {
                ForEach(AutomationDraft.ConditionKind.allCases) { Text($0.title).tag($0) }
            }
            conditionDetail
        }
    }

    @ViewBuilder
    private var conditionDetail: some View {
        switch draft.condition {
        case .none:
            EmptyView()
        case .hours:
            hourPicker("From", selection: $draft.startHour)
            hourPicker("To", selection: $draft.endHour)
            error(.hours)
        case .activityActive, .activityInactive:
            Picker("Activity", selection: $draft.activityKind) {
                ForEach(Self.activityKinds, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
    }

    private var actionSection: some View {
        Section {
            Picker("Action", selection: $draft.action) {
                ForEach(AutomationDraft.ActionKind.allCases) { Text($0.title).tag($0) }
            }
            actionDetail
        } header: {
            Text("Then")
        } footer: {
            if let rule = draft.build() { Text(rule.summary) }
        }
    }

    @ViewBuilder
    private var actionDetail: some View {
        switch draft.action {
        case .presentIsland:
            TextField("Seconds", text: $draft.seconds, prompt: Text("3"))
            error(.seconds)
        case .showMessage:
            TextField("Message", text: $draft.message, prompt: Text("Plug in your charger"))
            error(.message)
        case .playSound:
            Picker("Sound", selection: $draft.sound) {
                ForEach(AutomationDraft.sounds, id: \.self) { Text($0).tag($0) }
            }
            error(.sound)
        case .openURL:
            TextField("Web address", text: $draft.url, prompt: Text("https://example.com"))
            error(.url)
        case .openApp:
            TextField("App name", text: $draft.app, prompt: Text("Music"))
            error(.app)
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(isNew ? "Add Rule" : "Save") { save() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: Helpers

    private func hourPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(0..<24, id: \.self) { Text(AutomationFormat.hour($0)).tag($0) }
        }
    }

    @ViewBuilder
    private func error(_ field: AutomationDraft.Field) -> some View {
        if showErrors, let message = draft.errors[field] {
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }

    private func save() {
        guard let rule = draft.build() else {
            showErrors = true
            return
        }
        onSave(rule)
    }
}

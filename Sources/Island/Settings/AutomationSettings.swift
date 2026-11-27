import IslandCore
import SwiftUI

/// Lists automation rules and lets you add, edit, turn on or off, reorder and delete them.
/// `FeatureHub` isn't observable, so the view keeps a local copy and writes every change through to
/// `env.features.rules`, which persists on set.
struct AutomationSettings: View {
    let env: AppEnvironment
    @State private var rules: [AutomationRule]
    @State private var editing: RuleEditorTarget?
    @State private var pendingDelete: AutomationRule?

    init(env: AppEnvironment) {
        self.env = env
        _rules = State(initialValue: env.features.rules)
    }

    var body: some View {
        Form {
            Section {
                if rules.isEmpty {
                    Text("No rules yet.").foregroundStyle(.secondary)
                }
                ForEach(rules) { rule in
                    row(rule)
                }
                HStack {
                    Spacer()
                    Button("Add Rule…") { editing = RuleEditorTarget(draft: AutomationDraft(), isNew: true) }
                }
            } header: {
                Text("Rules")
            } footer: {
                Text("Rules run in order, from top to bottom, whenever their event happens. They can only show the Island, play a sound or open a page or app — never change system settings.")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { target in
            AutomationRuleEditor(draft: target.draft, isNew: target.isNew, onSave: save, onCancel: { editing = nil })
        }
        .confirmationDialog(deleteTitle, isPresented: isConfirmingDelete, titleVisibility: .visible, presenting: pendingDelete) { rule in
            Button("Delete Rule", role: .destructive) { commit(rules.removing(id: rule.id)) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private func row(_ rule: AutomationRule) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                Text(rule.summary).font(.caption).foregroundStyle(.secondary)
            }
            .opacity(rule.enabled ? 1 : 0.6)
            Spacer()
            Button("Edit…") { edit(rule) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit \(rule.name)")
            Toggle("Enabled", isOn: enabledBinding(rule))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Turn on \(rule.name)")
        }
        .contentShape(Rectangle())
        .contextMenu { contextMenu(rule) }
    }

    @ViewBuilder
    private func contextMenu(_ rule: AutomationRule) -> some View {
        Button("Edit…") { edit(rule) }
        Button("Move Up") { commit(rules.moving(id: rule.id, by: -1)) }
            .disabled(rules.first?.id == rule.id)
        Button("Move Down") { commit(rules.moving(id: rule.id, by: 1)) }
            .disabled(rules.last?.id == rule.id)
        Divider()
        Button("Delete…", role: .destructive) { pendingDelete = rule }
    }

    // MARK: State

    private var deleteTitle: String { "Delete “\(pendingDelete?.name ?? "")”?" }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func enabledBinding(_ rule: AutomationRule) -> Binding<Bool> {
        Binding(get: { rules.first { $0.id == rule.id }?.enabled ?? false },
                set: { commit(rules.setting(enabled: $0, for: rule.id)) })
    }

    private func edit(_ rule: AutomationRule) {
        editing = RuleEditorTarget(draft: AutomationDraft(rule: rule), isNew: false)
    }

    private func save(_ rule: AutomationRule) {
        commit(rules.upserting(rule))
        editing = nil
    }

    private func commit(_ updated: [AutomationRule]) {
        rules = updated
        env.features.rules = updated
    }
}

private struct RuleEditorTarget: Identifiable {
    let id = UUID()
    let draft: AutomationDraft
    let isNew: Bool
}

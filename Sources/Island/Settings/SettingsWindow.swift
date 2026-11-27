import AppKit
import IslandCore
import SwiftUI

/// The panes of Island's settings window — a standard macOS toolbar window (HIG › Settings: a few
/// panes in a fixed toolbar, the title names the pane, the last pane reopens). Kept deliberately
/// short: good defaults instead of knobs, and nothing that duplicates System Settings.
enum SettingsPane: String, CaseIterable {
    case general = "General", appearance = "Appearance", activities = "Activities"
    case teleprompter = "Teleprompter", advanced = "Advanced"

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .activities: "square.stack.3d.up"
        case .teleprompter: "text.alignleft"
        case .advanced: "gearshape.2"
        }
    }

    /// Each pane gets the height its content needs; the window resizes to fit (no scrolling).
    var height: CGFloat {
        switch self {
        case .general: 520
        case .appearance: 300
        case .activities: 620
        case .teleprompter: 600
        case .advanced: 600
        }
    }

    static let width: CGFloat = 620

    @MainActor @ViewBuilder
    func view(settings: IslandSettings, env: AppEnvironment) -> some View {
        switch self {
        case .general: GeneralPane(settings: settings, env: env)
        case .appearance: AppearanceSettings(settings: settings)
        case .activities: ActivitySettings(settings: settings, env: env)
        case .teleprompter: TeleprompterSettings(settings: settings, env: env)
        case .advanced: AdvancedPane(settings: settings, env: env)
        }
    }
}

// MARK: - General

struct GeneralPane: View {
    @Bindable var settings: IslandSettings
    let env: AppEnvironment
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { settings.launchAtLogin }, set: { on in
                    loginError = LaunchAtLogin.set(on)
                    settings.launchAtLogin = loginError == nil ? on : LaunchAtLogin.isEnabled
                }))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Picker("Show on", selection: $settings.display) {
                    Text("Built-in display").tag(DisplaySelection.automatic)
                    Text("Main display").tag(DisplaySelection.main)
                    ForEach(env.display.screens, id: \.id) { s in
                        Text(s.name).tag(DisplaySelection.specific(name: s.name))
                    }
                }
                Toggle("Hide when an app is full screen", isOn: $settings.hideInFullScreen)
            }
            Section {
                Toggle("Open when the pointer is over the notch", isOn: $settings.hoverExpansion)
                Toggle(isOn: $settings.quietMode) {
                    Text("Quiet mode")
                    Text("Nothing opens by itself. Critical alerts still show.")
                }
            }
            Section("Keyboard") {
                LabeledContent("Search") { ShortcutRecorder(shortcut: $settings.searchShortcut) }
                if let conflict = shortcutConflict {
                    Text(conflict).font(.caption).foregroundStyle(.orange)
                }
                LabeledContent("Open Island") { ShortcutRecorder(shortcut: $settings.islandShortcut) }
                Toggle("Include files in search", isOn: $settings.fileSearchEnabled)
            }
            Section { UpdatesRow(settings: settings, updates: env.updates) }
        }
        .formStyle(.grouped)
    }

    /// macOS refuses a hot key another app already owns; well-known launchers may also take ⌥Space.
    private var shortcutConflict: String? {
        guard settings.searchEnabled, settings.islandEnabled else { return nil }
        if let error = env.features.hotKey?.lastError, error != noErr {
            return "\(settings.searchShortcut.display) is used by another app or macOS. Choose another shortcut."
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let owners = ShortcutConflicts.likelyOwners(of: settings.searchShortcut, running: running)
        guard !owners.isEmpty else { return nil }
        return "\(owners.joined(separator: " and ")) also uses \(settings.searchShortcut.display). If search doesn't open, change one shortcut."
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    @Bindable var settings: IslandSettings
    let env: AppEnvironment
    @State private var braveKey = Keychain.get(account: "brave-search") ?? ""
    @State private var editingRules = false
    @State private var confirmingReset = false

    var body: some View {
        Form {
            Section {
                Toggle("Suggestions on Home", isOn: $settings.homeSuggestions)
                Button("Clear Usage History") { env.home.clearHistory() }
            } footer: {
                Text("To add or remove pins, right-click Home in the Island.")
            }
            Section {
                Toggle("Experimental features", isOn: $settings.experimentalFeatures)
                if settings.experimentalFeatures {
                    Toggle("Web results in search", isOn: $settings.webSearchEnabled)
                    if settings.webSearchEnabled {
                        providerToggle("wikipedia", "Wikipedia")
                        providerToggle("duckduckgo", "DuckDuckGo")
                        providerToggle("brave", "Brave Search")
                        if settings.webSearchProviders.contains("brave") {
                            SecureField("Brave API key", text: $braveKey, prompt: Text("Paste your key"))
                                .onSubmit { try? Keychain.set(braveKey, account: "brave-search") }
                                .onDisappear { try? Keychain.set(braveKey, account: "brave-search") }
                        }
                    }
                    LabeledContent("Automation") { Button("Edit Rules…") { editingRules = true } }
                }
            } footer: {
                Text("Web results, AI answers and automation rules. Still being refined.")
            }
            if settings.experimentalFeatures { AISection(settings: settings) }
            #if DEBUG
            Section("Developer") {
                Toggle("Debug mode", isOn: $settings.debugMode)
                Toggle("Performance overlay", isOn: $settings.performanceOverlay)
                Button("Open Debug Panel") { env.showDebugPanel() }
            }
            #endif
            Section {
                Button("Reset All Settings…", role: .destructive) { confirmingReset = true }
                LabeledContent("Version", value: Self.version)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $editingRules) {
            VStack(spacing: 0) {
                AutomationSettings(env: env)
                HStack { Spacer(); Button("Done") { editingRules = false }.keyboardShortcut(.defaultAction) }
                    .padding(16)
            }
            .frame(width: 560, height: 480)
        }
        .confirmationDialog("Reset all settings?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { settings.resetToDefaults() }
        } message: {
            Text("Every setting goes back to its default. Your pins return to the defaults and your script is cleared.")
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let b = info?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    private func providerToggle(_ id: String, _ title: String) -> some View {
        Toggle(title, isOn: Binding(get: { settings.webSearchProviders.contains(id) }, set: { on in
            if on { settings.webSearchProviders.insert(id) } else { settings.webSearchProviders.remove(id) }
        }))
    }
}

// MARK: - Window

/// A toolbar tab view controller: each pane is a toolbar item, the window title follows the
/// selection, and the window resizes to the pane. The last pane reopens next time.
final class SettingsTabController: NSTabViewController {
    static let lastPaneKey = "island.settings.lastPane"

    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        guard let item, let window = view.window else { return }
        window.title = item.label
        UserDefaults.standard.set(item.label, forKey: Self.lastPaneKey)
        guard let size = item.viewController?.preferredContentSize, size != .zero else { return }
        // Resize around the top edge, animated, the way Mac settings windows change panes.
        let content = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var frame = window.frame
        frame.origin.y += frame.height - content.height
        frame.size = content.size
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    static func makeWindow(settings: IslandSettings, env: AppEnvironment, selecting pane: SettingsPane? = nil) -> NSWindow {
        let tabs = SettingsTabController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.allowUserInteraction] // no crossfade: the pane swaps, the window resizes
        for p in SettingsPane.allCases {
            let host = NSHostingController(rootView: AnyView(p.view(settings: settings, env: env)
                .frame(width: SettingsPane.width, height: p.height)))
            host.preferredContentSize = NSSize(width: SettingsPane.width, height: p.height)
            let item = NSTabViewItem(viewController: host)
            item.label = p.rawValue
            item.image = NSImage(systemSymbolName: p.symbol, accessibilityDescription: p.rawValue)
            tabs.addTabViewItem(item)
        }
        let last = pane?.rawValue ?? UserDefaults.standard.string(forKey: SettingsTabController.lastPaneKey)
        let index = SettingsPane.allCases.firstIndex { $0.rawValue == last } ?? 0
        tabs.selectedTabViewItemIndex = index // before the window exists, so it opens on that pane
        let w = NSWindow(contentViewController: tabs)
        // HIG: settings windows dim minimize and zoom; the window sizes to each pane.
        w.styleMask = [.titled, .closable]
        w.toolbarStyle = .preference
        w.isReleasedWhenClosed = false
        w.title = SettingsPane.allCases[index].rawValue
        w.setContentSize(NSSize(width: SettingsPane.width, height: SettingsPane.allCases[index].height))
        return w
    }

    func show(env: AppEnvironment) {
        if window == nil {
            let w = Self.makeWindow(settings: env.settings, env: env)
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

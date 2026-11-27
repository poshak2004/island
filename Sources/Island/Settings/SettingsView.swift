import AppKit
import IslandCore
import SwiftUI

struct ActivitySettings: View {
    @Bindable var settings: IslandSettings
    let env: AppEnvironment
    static let configurable: [(ActivityKind, String)] = [
        (.media, "Music, Spotify, VLC"), (.timer, "Countdown timers"), (.download, "Safari, Chrome & Finder downloads"),
        (.recording, "Shows when an app uses the mic or camera"), (.battery, "Charging, low battery, full"),
        (.network, "When you go offline"), (.device, "AirPods, headphones and speakers connecting"),
        (.calendar, "Upcoming events (asks for Calendar access)"), (.clipboard, "Local “Copied” confirmations"),
        (.notification, "Short system events"),
        (.teleprompter, "Scrolling script under the camera"),
        (.shelf, "Drag files to the notch to keep or AirDrop them"),
    ]

    private func quietBinding(_ kind: ActivityKind) -> Binding<Bool> {
        Binding(get: { settings.quietKinds.contains(kind) }, set: { quiet in
            if quiet { settings.quietKinds.insert(kind) } else { settings.quietKinds.remove(kind) }
        })
    }

    var body: some View {
        Form {
            Section {
                ForEach(Self.configurable, id: \.0) { kind, detail in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading) { Text(kind.displayName); Text(detail).font(.caption).foregroundStyle(.secondary) }
                        Spacer(minLength: 8)
                        Picker("", selection: quietBinding(kind)) {
                            Text("Pop Up").tag(false)
                            Text("Quiet").tag(true)
                        }
                        .pickerStyle(.menu)
                        .buttonStyle(.borderless)
                        .labelsHidden()
                        .fixedSize()
                        .disabled(!settings.enabledKinds.contains(kind))
                        .help("Quiet: updates the Island without opening it or taking over.")
                        .accessibilityLabel("\(kind.displayName) presentation")
                        Toggle("", isOn: Binding(get: { settings.enabledKinds.contains(kind) }, set: { on in
                            if on { settings.enabledKinds.insert(kind) } else { settings.enabledKinds.remove(kind) }
                        }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(kind.displayName)
                    }
                }
            }
            Section {
                Toggle("Browser media (Safari, Chrome, Brave, Edge)", isOn: $settings.browserMediaEnabled)
            } footer: {
                Text("Requires “Allow JavaScript from Apple Events” in the browser's Develop/Developer menu. Island reads the playing media's title and position; it checks tabs every few seconds while the browser is open.")
            }
            if env.settings.enabledKinds.contains(.calendar) {
                LabeledContent("Calendar", value: env.calendar.status).font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}

/// Search › AI answers (Experimental; was its own pane).
struct AISection: View {
    @Bindable var settings: IslandSettings
    @State private var key = ""

    var body: some View {
        Section {
            Picker("Provider", selection: $settings.aiProvider) {
                ForEach(AIProviderKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            if settings.aiProvider != .none {
                TextField("Model", text: $settings.aiModel, prompt: Text(AIProviderFactory.defaultModel(settings.aiProvider)))
                if settings.aiProvider != .ollama {
                    SecureField("API key (stored in Keychain)", text: $key, prompt: Text("Paste your key"))
                        .onAppear { key = Keychain.get(account: settings.aiProvider.rawValue) ?? "" }
                        .onChange(of: settings.aiProvider) { _, p in key = Keychain.get(account: p.rawValue) ?? "" }
                        .onSubmit { save() }
                        .onDisappear { save() }
                }
            }
        } header: {
            Text("AI Answers")
        } footer: {
            Text("Ask questions from search with “ask …” or by ending with “?”. Island searches the web, fetches sources, and shows a short answer with citations. AI can only return text — it cannot run commands or change your system.")
        }
    }

    private func save() { try? Keychain.set(key, account: settings.aiProvider.rawValue) }
}

/// Click, then press the new key combination (must include ⌘, ⌥ or ⌃).
struct ShortcutRecorder: View {
    @Binding var shortcut: IslandShortcut
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press shortcut…" : shortcut.display) { recording ? stop() : start() }
            .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if e.keyCode == 53 { stop(); return nil }
            guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
            shortcut = IslandShortcut(keyCode: UInt32(e.keyCode), carbonModifiers: HotKey.carbonModifiers(from: flags),
                                        display: HotKey.display(keyCode: e.keyCode, characters: e.charactersIgnoringModifiers, flags: flags))
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

/// Settings › General: automatic checks, Check Now, and where things stand.
struct UpdatesRow: View {
    @Bindable var settings: IslandSettings
    let updates: UpdateService

    var body: some View {
        Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
        LabeledContent {
            HStack(spacing: 8) {
                if let update = updates.available {
                    Button("Download \(update.version) (build \(update.build))…") { NSWorkspace.shared.open(update.page) }
                } else {
                    Button("Check Now") { updates.checkNow() }
                        .disabled(updates.status == .checking)
                }
            }
        } label: {
            Text("Updates")
            Text(statusText).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if updates.available != nil { return "A newer build is available on GitHub." }
        switch updates.status {
        case .idle: return "Asks GitHub once a day. Nothing about you is sent."
        case .checking: return "Checking…"
        case .upToDate: return "Island is up to date."
        case .failed(let message): return message
        }
    }
}

struct AppearanceSettings: View {
    @Bindable var settings: IslandSettings
    var body: some View {
        Form {
            Section {
                LabeledContent("Glass intensity") {
                    HStack { Slider(value: $settings.glassIntensity, in: 0...1); Text("\(Int(settings.glassIntensity * 100))%").monospacedDigit().frame(width: 40) }
                }
                Toggle("See-through compact Island", isOn: $settings.compactGlass)
                    .help("Off matches Apple's Dynamic Island: solid black, so it reads as part of the hardware.")
                Toggle("Show song title in compact Island", isOn: $settings.compactShowsTitle)
                LabeledContent("Corner radius") {
                    HStack { Slider(value: $settings.cornerRadius, in: 12...48); Text("\(Int(settings.cornerRadius))").monospacedDigit().frame(width: 40) }
                }
            } footer: {
                Text("Glass intensity controls how see-through the Island is. The empty Island stays black so it disappears into the notch. Liquid Glass is used on macOS 26 and later.")
            }
        }
        .formStyle(.grouped)
    }
}

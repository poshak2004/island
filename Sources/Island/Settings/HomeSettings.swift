import AppKit
import IslandCore
import SwiftUI
import UniformTypeIdentifiers

/// Everything on the Island's home: reorder or remove pins, add websites and files (which need typing
/// or a file picker), and control suggestions.
struct HomeSettings: View {
    @Bindable var settings: IslandSettings
    let env: AppEnvironment
    @State private var siteTitle = ""
    @State private var siteURL = ""
    @State private var siteError: String?
    @State private var shortcutNames: [String] = []
    @State private var shortcutToAdd = ""

    var body: some View {
        Form {
            Section {
                if settings.homePins.isEmpty {
                    Text("Nothing pinned yet.").foregroundStyle(.secondary)
                }
                List {
                    ForEach(settings.homePins) { item in
                        HStack(spacing: 10) {
                            HomeTile(item: item) {}
                                .scaleEffect(0.6)
                                .frame(width: 38, height: 38)
                                .allowsHitTesting(false)
                                .environment(\.colorScheme, .dark)
                            VStack(alignment: .leading) {
                                Text(item.title)
                                Text(kind(of: item)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { env.home.unpin(item) } label: { Image(systemName: "minus.circle.fill") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(item.title)")
                        }
                    }
                    .onMove { from, to in settings.homePins.move(fromOffsets: from, toOffset: to) }
                }
                .frame(minHeight: CGFloat(max(1, settings.homePins.count)) * 46)
            } header: {
                Text("Pinned (\(settings.homePins.count) of \(HomePins.maxPins))")
            } footer: {
                Text("Drag to reorder. In the Island, click ＋ to add Island features, apps and Shortcuts, or right-click any search result and choose Pin to Home.")
            }

            Section("Add") {
                HStack {
                    TextField("Name", text: $siteTitle).frame(maxWidth: 160)
                    TextField("https://…", text: $siteURL).onSubmit(addWebsite)
                    Button("Add Website", action: addWebsite).disabled(siteURL.isEmpty)
                }
                if let siteError { Text(siteError).font(.caption).foregroundStyle(.red) }
                HStack {
                    Button("Add App…") { pickFile(apps: true) }
                    Button("Add File or Folder…") { pickFile(apps: false) }
                    Spacer()
                    if !shortcutNames.isEmpty {
                        Picker("Shortcut", selection: $shortcutToAdd) {
                            ForEach(shortcutNames, id: \.self) { Text($0).tag($0) }
                        }
                        .frame(maxWidth: 220)
                        Button("Add") { env.home.pin(.shortcut(name: shortcutToAdd)) }.disabled(shortcutToAdd.isEmpty)
                    }
                }
            }

            Section {
                Toggle("Suggestions", isOn: $settings.homeSuggestions)
                Button("Clear Usage History") { env.home.clearHistory() }
                Button("Reset Home to Defaults") { settings.homePins = HomePins.defaults }
            } footer: {
                Text("Suggestions show meetings you can join (with Calendar on), downloads to keep, and things you open often. What you open is remembered only on this Mac.")
            }
        }
        .formStyle(.grouped)
        .task {
            shortcutNames = await env.shortcuts.names()
            shortcutToAdd = shortcutNames.first ?? ""
        }
    }

    private func kind(of item: HomeItem) -> String {
        switch item {
        case .feature: "Island"
        case .app: "App"
        case .shortcut: "Shortcut"
        case .website(let url, _): url.host ?? "Website"
        case .file(let path, _): (path as NSString).abbreviatingWithTildeInPath
        }
    }

    private func addWebsite() {
        let raw = siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = raw.contains("://") ? raw : "https://" + raw
        guard let url = URL(string: withScheme), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, host.contains(".") else {
            siteError = "Enter a web address like example.com or https://example.com."
            return
        }
        siteError = nil
        env.home.pin(.website(url: url, title: siteTitle.trimmingCharacters(in: .whitespaces).isEmpty ? host : siteTitle))
        siteTitle = ""
        siteURL = ""
    }

    private func pickFile(apps: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = !apps
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if apps {
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let name = url.deletingPathExtension().lastPathComponent
            env.home.pin(apps ? .app(path: url.path, name: name) : .file(path: url.path, name: url.lastPathComponent))
        }
    }
}

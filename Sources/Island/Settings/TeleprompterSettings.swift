import AppKit
import IslandCore
import SwiftUI
import UniformTypeIdentifiers

/// Script editor and reading options. The script is saved as you type; Start opens it in the Island.
struct TeleprompterSettings: View {
    @Bindable var settings: IslandSettings
    let env: AppEnvironment
    @State private var notice: String?
    @State private var info: String?
    @State private var dropTargeted = false
    @State private var confirmingClear = false
    /// Short scripts clear at once; longer ones ask first (there's no undo once it's saved).
    static let confirmClearAboveWords = 20

    private var wordCount: Int { ScriptMatcher.normalize(settings.teleprompterScript).filter { !$0.isEmpty }.count }
    private var readingTime: String {
        DurationFormatter.spoken(Double(wordCount) / max(1, settings.teleprompterSpeed) * 60)
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.teleprompterScript)
                    .font(.system(size: 13))
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel("Script")
                    .overlay {
                        if dropTargeted {
                            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                        ShelfDrop.load(providers) { urls in urls.first.map(loadFile) }
                        return true
                    }
                HStack {
                    Text(wordCount == 0 ? "Type, paste or drop a .txt or .md file." : "\(wordCount) words · about \(readingTime)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear", role: .destructive) {
                        if wordCount > Self.confirmClearAboveWords { confirmingClear = true } else { clearScript() }
                    }
                    .disabled(settings.teleprompterScript.isEmpty)
                    .help("Remove the whole script.")
                    .confirmationDialog("Clear the script?", isPresented: $confirmingClear) {
                        Button("Clear Script", role: .destructive) { clearScript() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("All \(wordCount) words will be removed. This can't be undone.")
                    }
                    Button("Open File…") { openFile() }
                        .help("Load a plain text or Markdown file. You can also drop one onto the script.")
                    Button("Paste from Clipboard") { pasteClipboard() }
                    Button(env.teleprompter.isActive ? "Restart in Island" : "Start in Island") { start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(wordCount == 0)
                }
                if let notice { Text(notice).font(.caption).foregroundStyle(.red) }
                if let info { Text(info).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("Script")
            } footer: {
                Text("You can also type “teleprompter” in Island search (\(settings.searchShortcut.display)) or use the menu bar. Esc collapses the teleprompter; it keeps your place.")
            }

            Section("Reading") {
                LabeledContent("Speed") {
                    HStack {
                        Slider(value: $settings.teleprompterSpeed, in: TeleprompterActivity.speedRange, step: TeleprompterActivity.speedStep)
                        Text("\(Int(settings.teleprompterSpeed)) wpm").monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                }
                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $settings.teleprompterFontSize, in: IslandSettings.teleprompterFontRange, step: 1)
                        Text("\(Int(settings.teleprompterFontSize)) pt").monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                }
                Toggle("Pause while the pointer is over the Island", isOn: $settings.teleprompterPauseOnHover)
                Toggle(isOn: $settings.teleprompterVoiceFollow) {
                    VStack(alignment: .leading) {
                        Text("Follow my voice")
                        Text("Scrolls as you speak, using on-device speech recognition. Asks for microphone and speech access.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = env.teleprompter.lastVoiceError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Hide the Island from screen sharing and recordings", isOn: $settings.teleprompterHideFromCapture)
                Toggle("Open the teleprompter when the camera turns on", isOn: $settings.teleprompterStartWithCamera)
            } header: {
                Text("Calls and recordings")
            } footer: {
                Text("Hiding works with apps that respect macOS window sharing settings. Check once with your recording app before relying on it. When the camera turns on, the script opens paused so it never runs ahead of you.")
            }
        }
        .formStyle(.grouped)
    }

    private func pasteClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            notice = "The clipboard doesn't contain text."
            info = nil
            return
        }
        notice = nil
        info = nil
        settings.teleprompterScript = String(text.prefix(TeleprompterScript.maxCharacters))
    }

    private func clearScript() {
        settings.teleprompterScript = ""
        notice = nil
        info = "Script cleared."
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ScriptFile.contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Open Script"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFile(url)
    }

    private func loadFile(_ url: URL) {
        switch ScriptFile.read(url) {
        case let .success(imported):
            settings.teleprompterScript = imported.text
            notice = nil
            info = imported.truncated
                ? "“\(url.lastPathComponent)” was too long, so only the first \(TeleprompterScript.maxCharacters.formatted()) characters were loaded."
                : "Loaded “\(url.lastPathComponent)”."
        case let .failure(failure):
            notice = failure.message
            info = nil
        }
    }

    private func start() {
        notice = nil
        env.teleprompter.start(text: settings.teleprompterScript, title: "Teleprompter", autoplay: true)
    }
}

/// Reads a script file off disk. Decoding and Markdown stripping live in IslandCore.
enum ScriptFile {
    static let contentTypes: [UTType] = [.plainText] + [UTType(filenameExtension: "md")].compactMap { $0 }
    /// Far above `TeleprompterScript.maxCharacters`; stops a stray huge file from being decoded.
    static let maxBytes = 8 * 1024 * 1024

    struct Failure: Error { let message: String }

    static func read(_ url: URL) -> Result<ScriptImport, Failure> {
        let name = url.lastPathComponent
        guard isReadableType(url) else { return .failure(Failure(message: "“\(name)” isn't a text or Markdown file.")) }
        let data: Data
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= maxBytes else { return .failure(Failure(message: "“\(name)” is too large for a script.")) }
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            return .failure(Failure(message: "Couldn't read “\(name)”: \(error.localizedDescription)"))
        }
        switch TeleprompterScript.importText(data: data, fileExtension: url.pathExtension) {
        case let .success(imported): return .success(imported)
        case .failure(.empty): return .failure(Failure(message: "“\(name)” has no text to read."))
        }
    }

    static func isReadableType(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if TeleprompterScript.markdownExtensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .plainText)
    }
}

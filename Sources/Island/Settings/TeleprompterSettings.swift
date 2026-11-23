import AppKit
import IslandCore
import SwiftUI

/// Script editor and reading options. The script is saved as you type; Start opens it in the Island.
struct TeleprompterSettings: View {
    @Bindable var settings: IslandSettings
    let env: AppEnvironment
    @State private var notice: String?

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
                HStack {
                    Text(wordCount == 0 ? "Paste or type your script." : "\(wordCount) words · about \(readingTime)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Paste from Clipboard") { pasteClipboard() }
                    Button(env.teleprompter.isActive ? "Restart in Island" : "Start in Island") { start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(wordCount == 0)
                }
                if let notice { Text(notice).font(.caption).foregroundStyle(.red) }
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
            return
        }
        notice = nil
        settings.teleprompterScript = String(text.prefix(TeleprompterScript.maxCharacters))
    }

    private func start() {
        notice = nil
        env.teleprompter.start(text: settings.teleprompterScript, title: "Teleprompter", autoplay: true)
    }
}

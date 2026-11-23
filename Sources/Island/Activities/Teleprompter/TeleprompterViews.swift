import IslandCore
import SwiftUI

enum TeleprompterStyle {
    static let tint = Color(red: 0.42, green: 0.86, blue: 0.74)
    static let symbol = "text.alignleft"
    /// Rows visible in the reading window; the reading line is the second, right under the camera.
    static let visibleRows: CGFloat = 4
    static let readingRow: CGFloat = 1
    static func lineHeight(fontSize: CGFloat) -> CGFloat { (fontSize * 1.38).rounded() }

    /// Approximate characters per line for a width (system font, semibold).
    static func lineCharacters(width: CGFloat, fontSize: CGFloat) -> Int {
        max(12, Int(width / (fontSize * 0.47)))
    }

    static func status(_ a: TeleprompterActivity) -> String {
        switch a.state {
        case .finished: "Finished"
        case .paused: "Paused"
        case .playing:
            if a.hoverPaused { "Paused while pointer is here" }
            else if a.voiceFollow { a.listening ? "Following your voice" : "Starting microphone…" }
            else { "\(Int(a.wordsPerMinute)) words per minute" }
        }
    }
}

private struct TeleprompterFontKey: EnvironmentKey { static let defaultValue: CGFloat = 22 }
private struct TeleprompterReadyKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// A script is saved and no session is running: offer to start one (e.g. when the camera turns on).
    var teleprompterReady: Bool {
        get { self[TeleprompterReadyKey.self] }
        set { self[TeleprompterReadyKey.self] = newValue }
    }
    var teleprompterFontSize: CGFloat {
        get { self[TeleprompterFontKey.self] }
        set { self[TeleprompterFontKey.self] = newValue }
    }
}

// MARK: Compact / minimal

struct TeleprompterCompactLeading: View {
    let prompter: TeleprompterActivity
    var body: some View {
        Image(systemName: prompter.voiceFollow ? "waveform" : TeleprompterStyle.symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(TeleprompterStyle.tint)
    }
}

struct TeleprompterCompactTrailing: View {
    let prompter: TeleprompterActivity
    @Environment(\.islandContentActive) private var active
    var body: some View {
        TimelineView(.periodic(from: .now, by: clockInterval(active: active, running: prompter.rate > 0))) { ctx in
            ProgressRing(fraction: prompter.progress(at: ctx.date), tint: TeleprompterStyle.tint, lineWidth: 2.5)
                .frame(width: 15, height: 15)
        }
    }
}

struct TeleprompterMinimal: View {
    let prompter: TeleprompterActivity
    var body: some View {
        ZStack {
            ProgressRing(fraction: prompter.progress(at: Date()), tint: TeleprompterStyle.tint, lineWidth: 2)
            Image(systemName: TeleprompterStyle.symbol).font(.system(size: 8, weight: .bold)).foregroundStyle(TeleprompterStyle.tint)
        }
        .padding(2)
    }
}

// MARK: Expanded

struct TeleprompterExpanded: View {
    let prompter: TeleprompterActivity
    @Environment(\.islandCommands) private var send
    @Environment(\.islandContentActive) private var active
    @Environment(\.islandReduceMotion) private var reduceMotion
    @Environment(\.teleprompterFontSize) private var fontSize

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !(active && prompter.rate > 0))) { ctx in
                ScriptWindow(script: prompter.script, offset: prompter.lineOffset(at: ctx.date), fontSize: fontSize)
            }
            // Voice follow moves in steps; ease between them instead of jumping.
            .animation(prompter.voiceFollow && !reduceMotion ? .easeOut(duration: 0.35) : nil, value: prompter.anchorWord)
            TimelineView(.periodic(from: .now, by: clockInterval(active: active, running: prompter.rate > 0))) { ctx in
                LinearProgress(fraction: prompter.progress(at: ctx.date), tint: TeleprompterStyle.tint, height: 3)
            }
            .accessibilityHidden(true)
            controls
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Teleprompter")
    }

    private var controls: some View {
        HStack(spacing: 6) {
            IslandIconButton(symbol: "backward.fill", size: 12, label: "Previous line") { send(.teleprompter(.skip(lines: -1))) }
            IslandIconButton(symbol: prompter.state == .playing ? "pause.fill" : "play.fill", size: 15,
                             label: prompter.state == .playing ? "Pause" : "Play", prominent: true) {
                send(.teleprompter(.togglePlayPause))
            }
            .contentTransition(.symbolEffect(.replace))
            IslandIconButton(symbol: "forward.fill", size: 12, label: "Next line") { send(.teleprompter(.skip(lines: 1))) }
            Text(TeleprompterStyle.status(prompter))
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(IslandPalette.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            if !prompter.voiceFollow {
                IslandIconButton(symbol: "minus", size: 11, label: "Slower", enabled: prompter.wordsPerMinute > TeleprompterActivity.speedRange.lowerBound) {
                    send(.teleprompter(.slower))
                }
                IslandIconButton(symbol: "plus", size: 11, label: "Faster", enabled: prompter.wordsPerMinute < TeleprompterActivity.speedRange.upperBound) {
                    send(.teleprompter(.faster))
                }
            }
            IslandIconButton(symbol: prompter.voiceFollow ? "mic.fill" : "mic", size: 12,
                             label: prompter.voiceFollow ? "Stop following my voice" : "Follow my voice") {
                send(.teleprompter(.toggleVoiceFollow))
            }
            IslandIconButton(symbol: "xmark", size: 11, label: "Close teleprompter") { send(.teleprompter(.stop)) }
        }
    }
}

/// Only the lines near the reading position are built, so long scripts cost the same as short ones.
private struct ScriptWindow: View {
    let script: TeleprompterScript
    let offset: Double
    let fontSize: CGFloat

    var body: some View {
        let lineHeight = TeleprompterStyle.lineHeight(fontSize: fontSize)
        let rows = TeleprompterStyle.visibleRows
        let first = max(0, Int(offset.rounded(.down)) - Int(TeleprompterStyle.readingRow) - 1)
        let last = min(script.lines.count - 1, Int(offset.rounded(.down)) + Int(rows) + 1)
        ZStack(alignment: .topLeading) {
            if first <= last {
                ForEach(first...last, id: \.self) { i in
                    let distance = Double(i) - offset
                    Text(script.lines[i].text)
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .opacity(abs(distance) < 0.6 ? 1 : max(0.28, 0.75 - abs(distance) * 0.16))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: lineHeight)
                        .offset(y: (CGFloat(i) - CGFloat(offset) + TeleprompterStyle.readingRow) * lineHeight)
                }
            }
        }
        .frame(height: lineHeight * rows, alignment: .top)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                     .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Script")
        .accessibilityValue(currentText)
    }

    private var currentText: String {
        let i = min(script.lines.count - 1, max(0, Int(offset.rounded(.down))))
        return script.lines.isEmpty ? "" : script.lines[i].text
    }
}

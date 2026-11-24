import IslandCore
import SwiftUI

/// One-time welcome, shown inside the Island itself on first launch (HIG › Onboarding: brief, teach
/// through the real surface, easy to skip). Three things people can't discover by looking at a black
/// notch — hover, the search shortcut, dropping files — plus the one choice worth making now.
struct WelcomeView: View {
    @Bindable var settings: IslandSettings
    @Environment(\.islandCommands) private var send
    @State private var loginError: String?

    private struct Tip: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { symbol }
    }

    private var tips: [Tip] {
        [
            Tip(symbol: "cursorarrow.motionlines", title: "Hover the notch",
                detail: "Island opens; move away and it settles back."),
            Tip(symbol: "magnifyingglass", title: "\(settings.searchShortcut.display) to search",
                detail: "Apps, files and actions, from anywhere."),
            Tip(symbol: "tray.and.arrow.down", title: "Drop files on the notch",
                detail: "Keep them on the shelf, or AirDrop them."),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Island")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Live activities, right in your notch.")
                    .font(.system(size: 13))
                    .foregroundStyle(IslandPalette.secondaryText)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(tips) { tip in
                    HStack(spacing: 12) {
                        Image(systemName: tip.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(.white.opacity(0.12)))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tip.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            Text(tip.detail).font(.system(size: 12)).foregroundStyle(IslandPalette.secondaryText)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            HStack(spacing: 12) {
                Toggle("Open at login", isOn: Binding(get: { settings.launchAtLogin }, set: { on in
                    loginError = LaunchAtLogin.set(on)
                    settings.launchAtLogin = loginError == nil ? on : LaunchAtLogin.isEnabled
                }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                Spacer(minLength: 8)
                Button("Done", action: finish)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
            }
            if let loginError {
                Text(loginError).font(.system(size: 11)).foregroundStyle(IslandPalette.batteryLow)
            }
        }
        .padding(.bottom, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Island")
    }

    private func finish() {
        settings.hasCompletedWelcome = true
        send(.ui(.collapse))
    }
}

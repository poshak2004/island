import IslandCore
import SwiftUI

/// What the Island shows when expanded with no live activity: time + quick actions.
struct HomeView: View {
    @Environment(\.islandCommands) private var send

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            TimelineView(.everyMinute) { ctx in
                VStack(alignment: .leading, spacing: 1) {
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.system(size: 30, weight: .light).monospacedDigit())
                        .foregroundStyle(.white)
                    Text(ctx.date, format: .dateTime.weekday(.wide).month().day())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(IslandPalette.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    IslandPillButton(title: "1m", symbol: "timer", tint: IslandPalette.timer) { send(.timer(.start(duration: 60, label: "Timer"))) }
                    IslandPillButton(title: "5m", symbol: nil, tint: IslandPalette.timer) { send(.timer(.start(duration: 300, label: "Timer"))) }
                    IslandPillButton(title: "25m", symbol: nil, tint: IslandPalette.timer) { send(.timer(.start(duration: 1500, label: "Focus"))) }
                }
                HStack(spacing: 6) {
                    IslandPillButton(title: "Search", symbol: "magnifyingglass") { send(.ui(.toggleSearch)) }
                    IslandIconButton(symbol: "gearshape.fill", size: 12, label: "Settings") { send(.openSettings) }
                }
            }
        }
    }
}

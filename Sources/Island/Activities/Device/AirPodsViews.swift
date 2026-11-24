import AppKit
import IslandCore
import SwiftUI

// MARK: - Environment

private struct AirPodsRevealedKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// False while the Island is still opening; the artwork waits for it (set by the root view).
    var airPodsRevealed: Bool {
        get { self[AirPodsRevealedKey.self] }
        set { self[AirPodsRevealedKey.self] = newValue }
    }
}

// MARK: - Artwork source

/// The product picture for an AirPods model, in order:
/// 1. a bundled, licensed, transparent render — `Island.app/Contents/Resources/AirPods/<model>.png`;
/// 2. the model's SF Symbol, drawn white with depth — crisp at any size, no tile behind it
///    (macOS's own device icons sit on a dark tile, which looked like a sticker in the Island).
@MainActor
enum AirPodsArtwork {
    private static var cache: [String: NSImage] = [:]

    static func render(model: AirPodsModel) -> NSImage? {
        if let cached = cache[model.rawValue] { return cached }
        for name in model.artworkNames {
            for ext in ["png", "heic", "tiff"] {
                if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "AirPods"),
                   let img = NSImage(contentsOf: url) {
                    cache[model.rawValue] = img
                    return img
                }
            }
        }
        return nil
    }

    static func symbol(model: AirPodsModel) -> String {
        switch model {
        case .airPodsPro, .airPodsPro2, .airPodsPro2USBC, .airPodsPro3: "airpods.pro"
        case .airPodsMax, .airPodsMaxUSBC: "airpods.max"
        case .airPods4, .airPods4ANC: "airpods.gen4"
        case .airPods3: "airpods.gen3"
        default: "airpods"
        }
    }
}

// MARK: - Artwork view

/// The product picture. Its entrance is one brief, precise move — scale 0.8 → 1 with opacity on a
/// low-bounce spring (HIG › Motion: "Add motion purposefully"; no tilt, glow or overshoot).
/// Waits until the Island has opened (`airPodsRevealed`).
struct AirPodsArtworkView: View {
    let model: AirPodsModel
    var size: CGFloat = 64
    var animatesEntrance = true
    @Environment(\.airPodsRevealed) private var revealed
    @Environment(\.islandReduceMotion) private var reduceMotion

    @State private var shown = false

    private static let entrance = Animation.spring(duration: 0.4, bounce: 0.15)
    private static let startScale: CGFloat = 0.8

    var body: some View {
        let visible = shown || !animatesEntrance
        artwork
            .frame(width: size, height: size)
            .scaleEffect(visible || reduceMotion ? 1 : Self.startScale)
            .opacity(visible ? 1 : 0)
            .accessibilityHidden(true)
            .onAppear { if revealed { enter() } }
            .onChange(of: revealed) { _, now in if now { enter() } }
    }

    @ViewBuilder private var artwork: some View {
        if let img = AirPodsArtwork.render(model: model) {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            // A symbol drawn as type, so its weight matches the adjacent semibold title (HIG › SF Symbols).
            Image(systemName: AirPodsArtwork.symbol(model: model))
                .font(.system(size: size * 0.6, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
    }

    private func enter() {
        guard !shown else { return }
        guard animatesEntrance, !reduceMotion else { shown = true; return }
        withAnimation(Self.entrance) { shown = true }
    }
}

// MARK: - Battery ring

/// Ring and number drawn from one animated value, so the arc sweeps and the digits count up together.
private struct BatteryRingFace: View, Animatable {
    var level: Double
    let target: Int
    let diameter: CGFloat

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    var body: some View {
        let line = max(2.5, diameter * 0.1)
        let tint = target <= 20 ? IslandPalette.batteryLow : IslandPalette.batteryGood
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: line)
            Circle()
                .trim(from: 0, to: CGFloat(level) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(level.rounded()))")
                .font(.system(size: diameter * 0.34, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                // Digits appear with the arc, so the sweep never flashes a "0".
                .opacity(target > 0 && level < 1 ? 0 : 1)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Battery as the system reports it: the lower bud as a ring with its percentage (left/right/case in
/// the accessibility label and tooltip). When it first appears in the revealed banner it fills from
/// empty — the iPhone's signature sweep. Hidden when nothing is reported — never guessed.
struct AirPodsBatteryView: View {
    let battery: AirPodsBattery?
    var diameter: CGFloat = 34
    /// Sweep up from zero on first show (the banner); compact shows the level directly.
    var sweeps = false
    var sweepDelay: Double = 0
    @Environment(\.airPodsRevealed) private var revealed
    @Environment(\.islandReduceMotion) private var reduceMotion
    @State private var shownLevel: Double = 0
    @State private var swept = false

    static let sweep = Animation.timingCurve(0.25, 0.9, 0.3, 1, duration: 0.95)

    var body: some View {
        if let battery, let level = battery.headline {
            BatteryRingFace(level: sweeps ? shownLevel : Double(level), target: level, diameter: diameter)
                .help(detail(battery))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Battery")
                .accessibilityValue(detail(battery))
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.8)))
                .onAppear { fill(to: level) }
                .onChange(of: revealed) { _, _ in fill(to: level) }
                .onChange(of: level) { _, new in fill(to: new) }
        }
    }

    private func fill(to level: Int) {
        guard sweeps, revealed else { return }
        if reduceMotion {
            shownLevel = Double(level)
        } else if swept {
            withAnimation(.smooth(duration: 0.3)) { shownLevel = Double(level) }
        } else {
            withAnimation(Self.sweep.delay(sweepDelay)) { shownLevel = Double(level) }
        }
        swept = true
    }

    private func detail(_ b: AirPodsBattery) -> String {
        if let s = b.single { return "\(s)%" }
        return [b.left.map { "Left \($0)%" }, b.right.map { "Right \($0)%" }, b.caseLevel.map { "Case \($0)%" }]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

// MARK: - Connection banner

/// The connection banner: `[ art ]  Name / Connected  ( ring )` in one short, wide row, like the
/// iPhone's. Art leads and battery trails, as in the compact presentation (HIG › Live Activities:
/// "Maintain the relative placement of elements"). The ring sweep is the one motion that carries
/// information — the level — so it's the one that gets time.
struct AirPodsConnectionView: View {
    let device: DeviceActivity
    let id: String
    @Environment(\.airPodsRevealed) private var revealed
    @Environment(\.islandReduceMotion) private var reduceMotion

    private var model: AirPodsModel { device.airPods ?? .unknownAirPods }
    private var title: String {
        let name = device.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? model.displayName : name
    }

    /// Spoken battery: every level the system reports, so VoiceOver users get left, right and case.
    private var batterySpoken: String {
        guard device.connected, let b = device.battery else { return "" }
        if let s = b.single { return "Battery \(s) percent" }
        return [b.left.map { "Left \($0) percent" }, b.right.map { "Right \($0) percent" },
                b.caseLevel.map { "Case \($0) percent" }].compactMap { $0 }.joined(separator: ", ")
    }

    private enum Layout {
        static let art: CGFloat = 40
        static let ring: CGFloat = 40
        static let row: CGFloat = 40
    }

    var body: some View {
        HStack(spacing: 12) {
            AirPodsArtworkView(model: model, size: Layout.art)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(device.connected ? "Connected" : "Disconnected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(IslandPalette.secondaryText)
            }
            .opacity(revealed ? 1 : 0)
            .blur(radius: revealed || reduceMotion ? 0 : 2)
            .animation(.smooth(duration: 0.3).delay(revealed ? 0.08 : 0), value: revealed)
            Spacer(minLength: 8)
            AirPodsBatteryView(battery: device.connected ? device.battery : nil, diameter: Layout.ring,
                               sweeps: true, sweepDelay: 0.18)
                .opacity(revealed ? 1 : 0)
                .animation(.easeOut(duration: 0.2).delay(revealed ? 0.12 : 0), value: revealed)
        }
        .frame(height: Layout.row)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: device.battery)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(device.connected ? "connected" : "disconnected")")
        .accessibilityValue(batterySpoken)
    }
}

// MARK: - Compact

struct DeviceCompactLeading: View {
    let device: DeviceActivity
    let id: String
    var body: some View {
        if let model = device.airPods {
            AirPodsArtworkView(model: model, size: 22, animatesEntrance: false)
        } else {
            SimpleCompactLeading(symbol: DevicePresentation.symbol(device), tint: .white, text: device.name, id: id)
        }
    }
}

/// Compact trailing: battery when known, otherwise a green check.
struct DeviceCompactTrailing: View {
    let device: DeviceActivity
    var body: some View {
        if device.connected, let level = device.battery?.headline {
            AirPodsBatteryView(battery: device.battery, diameter: 20)
                .accessibilityLabel("Battery \(level)%")
        } else {
            Image(systemName: device.connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(device.connected ? IslandPalette.batteryGood : .white.opacity(0.55))
                .accessibilityHidden(true)
        }
    }
}

/// Non-AirPods headphones keep the simple event card.
struct HeadphonesConnectedView: View {
    let device: DeviceActivity
    let id: String
    var body: some View {
        EventLikeExpanded(symbol: DevicePresentation.symbol(device), tint: .white, title: device.name,
                          subtitle: device.connected ? "Connected" : "Disconnected", id: id)
    }
}

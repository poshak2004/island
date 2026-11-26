import Foundation
import Observation

public struct IslandShortcut: Codable, Equatable, Sendable {
    /// Carbon virtual key code.
    public var keyCode: UInt32
    /// Carbon modifier mask (cmdKey, optionKey, controlKey, shiftKey).
    public var carbonModifiers: UInt32
    public var display: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.display = display
    }

    /// ⌥Space
    public static let defaultSearch = IslandShortcut(keyCode: 49, carbonModifiers: 0x0800, display: "⌥Space")
    /// ⌃⌥I — opens the Island with keyboard focus. (⌃⌥Space is taken by macOS input-source switching.)
    public static let defaultIsland = IslandShortcut(keyCode: 34, carbonModifiers: 0x1800, display: "⌃⌥I")
}

public enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case none, anthropic, openAI, ollama
    public var displayName: String {
        switch self {
        case .none: "Off"
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .ollama: "Local (Ollama)"
        }
    }
}

/// User preferences. Persisted to UserDefaults on every change.
@MainActor
@Observable
public final class IslandSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loading = false

    // General
    public var islandEnabled = true { didSet { save() } }
    public var launchAtLogin = false { didSet { save() } }
    public var display: DisplaySelection = .automatic { didSet { save() } }
    // Appearance
    public var glassIntensity: Double = 0.6 { didSet { save() } }
    public var islandScale: Double = 1.0 { didSet { save() } }
    public var cornerRadius: Double = 32 { didSet { save() } }
    /// Compact Island background: see-through glass (default) or solid black like the hardware notch.
    /// Off by default: Apple's Dynamic Island is opaque black so it reads as part of the hardware.
    public var compactGlass = false { didSet { save() } }
    /// Show the song title next to the artwork in the compact Island (wider; covers more menu bar).
    public var compactShowsTitle = false { didSet { save() } }
    // Behavior
    public var hoverExpansion = true { didSet { save() } }
    public var hoverDelay: Double = 0.06 { didSet { save() } }
    /// How long the Island stays open after the pointer leaves it.
    public var collapseDelay: Double = 0.7 { didSet { save() } }
    public var autoCollapse = true { didSet { save() } }
    public var autoCollapseDelay: Double = 4 { didSet { save() } }
    public var animationSpeed: Double = 1.0 { didSet { save() } }
    public var hapticFeedback = true { didSet { save() } }
    // Activities
    public var enabledKinds: Set<ActivityKind> = IslandSettings.defaultKinds { didSet { save() } }
    public var browserMediaEnabled = false { didSet { save() } }
    // Search
    public var searchEnabled = true { didSet { save() } }
    public var searchShortcut: IslandShortcut = .defaultSearch { didSet { save() } }
    public var islandShortcut: IslandShortcut = .defaultIsland { didSet { save() } }
    public var webSearchEnabled = true { didSet { save() } }
    public var webSearchProviders: Set<String> = ["wikipedia", "duckduckgo"] { didSet { save() } }
    public var fileSearchEnabled = true { didSet { save() } }
    // AI
    public var aiProvider: AIProviderKind = .none { didSet { save() } }
    /// Web results, AI answers and automation rules. Off by default: the Island's core is live
    /// activities; these stay available for people who opt in.
    public var experimentalFeatures = false { didSet { save() } }
    /// The one-time welcome in the Island (hover, search, shelf). Existing installs skip it.
    public var hasCompletedWelcome = false { didSet { save() } }
    /// Once a day, asks GitHub whether a newer build was published. Sends nothing about you.
    public var checkForUpdates = true { didSet { save() } }
    /// Nothing pops the Island open by itself and new events don't take over; critical alerts still do.
    public var quietMode = false { didSet { save() } }
    /// Activities that update quietly (never open the Island by themselves, never take over).
    public var quietKinds: Set<ActivityKind> = [] { didSet { save() } }
    /// Step aside while a full-screen app (video, presentation, game) is in front on the Island's display.
    public var hideInFullScreen = true { didSet { save() } }

    public func isQuiet(_ kind: ActivityKind) -> Bool { quietMode || quietKinds.contains(kind) }

    public var effectiveWebSearch: Bool { experimentalFeatures && webSearchEnabled }
    public var effectiveAIProvider: AIProviderKind { experimentalFeatures ? aiProvider : .none }
    public var automationEnabled: Bool { experimentalFeatures }
    public var aiModel: String = "" { didSet { save() } }
    // Accessibility (forced overrides on top of the system settings)
    public var forceReduceMotion = false { didSet { save() } }
    public var forceReduceTransparency = false { didSet { save() } }
    public var forceHighContrast = false { didSet { save() } }
    // Advanced
    public var debugMode = false { didSet { save() } }
    public var performanceOverlay = false { didSet { save() } }

    public var teleprompterScript = "" { didSet { save() } }
    public var teleprompterSpeed: Double = 140 { didSet { save() } }
    public var teleprompterFontSize: Double = 22 { didSet { save() } }
    /// Keep the Island out of screen shares and recordings while the teleprompter is showing.
    public var teleprompterHideFromCapture = true { didSet { save() } }
    public var teleprompterPauseOnHover = true { didSet { save() } }
    public var teleprompterVoiceFollow = false { didSet { save() } }
    /// Open the teleprompter (paused) when the camera turns on.
    public var teleprompterStartWithCamera = false { didSet { save() } }
    /// Your pinned items on the Island's home, in order.
    public var homePins: [HomeItem] = HomePins.defaults { didSet { save() } }
    /// Context suggestions (meetings, downloads, habits) above your pins.
    public var homeSuggestions = true { didSet { save() } }
    public static let teleprompterFontRange: ClosedRange<Double> = 14...34

    public static let defaultKinds: Set<ActivityKind> = [.media, .timer, .download, .recording, .battery, .network, .device, .search, .notification, .custom, .call, .teleprompter, .shelf]
    /// Bump when new default-on kinds are added, so existing installs get them once.
    static let kindsRevision = 2
    static let kindsAddedInRevision2: Set<ActivityKind> = [.teleprompter, .shelf]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    public func resetToDefaults() {
        let fresh = IslandSettings(defaults: UserDefaults(suiteName: "island.defaults.\(UUID().uuidString)")!)
        loading = true
        apply(fresh.snapshot())
        loading = false
        save()
    }

    // MARK: Persistence

    struct Snapshot: Codable {
        var islandEnabled: Bool?
        var launchAtLogin: Bool?
        var display: DisplaySelection?
        var glassIntensity: Double?
        var islandScale: Double?
        var cornerRadius: Double?
        var compactGlass: Bool?
        var compactShowsTitle: Bool?
        var collapseDelay: Double?
        var hoverExpansion: Bool?
        var hoverDelay: Double?
        var autoCollapse: Bool?
        var autoCollapseDelay: Double?
        var animationSpeed: Double?
        var hapticFeedback: Bool?
        var enabledKinds: [ActivityKind]?
        var browserMediaEnabled: Bool?
        var searchEnabled: Bool?
        var searchShortcut: IslandShortcut?
        var islandShortcut: IslandShortcut?
        var webSearchEnabled: Bool?
        var webSearchProviders: [String]?
        var fileSearchEnabled: Bool?
        var aiProvider: AIProviderKind?
        var experimentalFeatures: Bool?
        var hasCompletedWelcome: Bool?
        var checkForUpdates: Bool?
        var quietMode: Bool?
        var quietKinds: [ActivityKind]?
        var hideInFullScreen: Bool?
        var aiModel: String?
        var forceReduceMotion: Bool?
        var forceReduceTransparency: Bool?
        var forceHighContrast: Bool?
        var debugMode: Bool?
        var performanceOverlay: Bool?
        var kindsRevision: Int?
        var teleprompterScript: String?
        var teleprompterSpeed: Double?
        var teleprompterFontSize: Double?
        var teleprompterHideFromCapture: Bool?
        var teleprompterPauseOnHover: Bool?
        var teleprompterVoiceFollow: Bool?
        var teleprompterStartWithCamera: Bool?
        /// Lossy: one pin from a newer version (or a hand edit) can't wipe every other setting.
        var homePins: [Lossy<HomeItem>]?
        var homeSuggestions: Bool?
    }

    static let storageKey = "island.settings.v1"

    func snapshot() -> Snapshot {
        Snapshot(islandEnabled: islandEnabled, launchAtLogin: launchAtLogin, display: display, glassIntensity: glassIntensity,
                 islandScale: islandScale, cornerRadius: cornerRadius, compactGlass: compactGlass,
                 compactShowsTitle: compactShowsTitle, collapseDelay: collapseDelay, hoverExpansion: hoverExpansion, hoverDelay: hoverDelay,
                 autoCollapse: autoCollapse, autoCollapseDelay: autoCollapseDelay, animationSpeed: animationSpeed,
                 hapticFeedback: hapticFeedback, enabledKinds: enabledKinds.map { $0 }.sorted { $0.rawValue < $1.rawValue },
                 browserMediaEnabled: browserMediaEnabled, searchEnabled: searchEnabled, searchShortcut: searchShortcut, islandShortcut: islandShortcut,
                 webSearchEnabled: webSearchEnabled, webSearchProviders: webSearchProviders.sorted(),
                 fileSearchEnabled: fileSearchEnabled, aiProvider: aiProvider, experimentalFeatures: experimentalFeatures, hasCompletedWelcome: hasCompletedWelcome, checkForUpdates: checkForUpdates, quietMode: quietMode, quietKinds: quietKinds.map(\.rawValue).sorted().compactMap(ActivityKind.init(rawValue:)), hideInFullScreen: hideInFullScreen, aiModel: aiModel,
                 forceReduceMotion: forceReduceMotion, forceReduceTransparency: forceReduceTransparency,
                 forceHighContrast: forceHighContrast, debugMode: debugMode, performanceOverlay: performanceOverlay,
                 kindsRevision: Self.kindsRevision, teleprompterScript: teleprompterScript,
                 teleprompterSpeed: teleprompterSpeed, teleprompterFontSize: teleprompterFontSize,
                 teleprompterHideFromCapture: teleprompterHideFromCapture, teleprompterPauseOnHover: teleprompterPauseOnHover,
                 teleprompterVoiceFollow: teleprompterVoiceFollow, teleprompterStartWithCamera: teleprompterStartWithCamera,
                 homePins: homePins.map { Lossy(value: $0) }, homeSuggestions: homeSuggestions)
    }

    private func apply(_ s: Snapshot) {
        if let v = s.islandEnabled { islandEnabled = v }
        if let v = s.launchAtLogin { launchAtLogin = v }
        if let v = s.display { display = v }
        if let v = s.glassIntensity { glassIntensity = min(1, max(0, v)) }
        if let v = s.islandScale { islandScale = min(1.3, max(0.8, v)) }
        if let v = s.cornerRadius { cornerRadius = min(48, max(12, v)) }
        if let v = s.compactGlass { compactGlass = v }
        if let v = s.compactShowsTitle { compactShowsTitle = v }
        if let v = s.collapseDelay { collapseDelay = min(3, max(0.1, v)) }
        if let v = s.hoverExpansion { hoverExpansion = v }
        // 0.12 was the previous default; move untouched installs to the snappier one.
        if let v = s.hoverDelay { hoverDelay = v == 0.12 ? 0.06 : min(1, max(0, v)) }
        if let v = s.autoCollapse { autoCollapse = v }
        if let v = s.autoCollapseDelay { autoCollapseDelay = min(30, max(1, v)) }
        if let v = s.animationSpeed { animationSpeed = min(2, max(0.5, v)) }
        if let v = s.hapticFeedback { hapticFeedback = v }
        if let v = s.enabledKinds {
            var kinds = Set(v)
            if (s.kindsRevision ?? 1) < 2 { kinds.formUnion(Self.kindsAddedInRevision2) }
            enabledKinds = kinds
        }
        if let v = s.browserMediaEnabled { browserMediaEnabled = v }
        if let v = s.searchEnabled { searchEnabled = v }
        if let v = s.searchShortcut { searchShortcut = v }
        if let v = s.islandShortcut { islandShortcut = v }
        if let v = s.webSearchEnabled { webSearchEnabled = v }
        if let v = s.webSearchProviders { webSearchProviders = Set(v) }
        if let v = s.fileSearchEnabled { fileSearchEnabled = v }
        if let v = s.aiProvider { aiProvider = v }
        // Installs from before the switch existed: someone who set up AI keeps it.
        if let v = s.hasCompletedWelcome { hasCompletedWelcome = v }
        if let v = s.checkForUpdates { checkForUpdates = v }
        if let v = s.quietMode { quietMode = v }
        if let v = s.quietKinds { quietKinds = Set(v) }
        if let v = s.hideInFullScreen { hideInFullScreen = v }
        if let v = s.experimentalFeatures { experimentalFeatures = v } else if let p = s.aiProvider, p != .none { experimentalFeatures = true }
        if let v = s.aiModel { aiModel = v }
        if let v = s.forceReduceMotion { forceReduceMotion = v }
        if let v = s.forceReduceTransparency { forceReduceTransparency = v }
        if let v = s.forceHighContrast { forceHighContrast = v }
        if let v = s.debugMode { debugMode = v }
        if let v = s.performanceOverlay { performanceOverlay = v }
        if let v = s.teleprompterScript { teleprompterScript = String(v.prefix(TeleprompterScript.maxCharacters)) }
        if let v = s.teleprompterSpeed { teleprompterSpeed = TeleprompterActivity.clampSpeed(v) }
        if let v = s.teleprompterFontSize { teleprompterFontSize = min(Self.teleprompterFontRange.upperBound, max(Self.teleprompterFontRange.lowerBound, v)) }
        if let v = s.teleprompterHideFromCapture { teleprompterHideFromCapture = v }
        if let v = s.teleprompterPauseOnHover { teleprompterPauseOnHover = v }
        if let v = s.teleprompterVoiceFollow { teleprompterVoiceFollow = v }
        if let v = s.teleprompterStartWithCamera { teleprompterStartWithCamera = v }
        if let v = s.homePins { homePins = Array(v.compactMap(\.value).prefix(HomePins.maxPins)) }
        if let v = s.homeSuggestions { homeSuggestions = v }
    }

    static let unreadableBackupKey = storageKey + ".unreadable"

    private func load() {
        loading = true
        defer { loading = false }
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        // Saved settings mean this isn't a first run: existing users never see the welcome.
        hasCompletedWelcome = true
        if let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            apply(snap)
            return
        }
        // Something didn't decode (a value from a newer version, a hand edit). Keep the original for
        // recovery, then recover every field that still reads — one bad value must never reset the rest.
        defaults.set(data, forKey: Self.unreadableBackupKey)
        for snap in Self.recoverFields(from: data) { apply(snap) }
    }

    /// Decodes each top-level field on its own; fields that fail are dropped. Fields a migration reads
    /// together travel together: `kindsRevision` with `enabledKinds`, `experimentalFeatures` with `aiProvider`.
    static func recoverFields(from data: Data) -> [Snapshot] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let revision = object["kindsRevision"]
        let experimental = object["experimentalFeatures"]
        return object.compactMap { key, value in
            var single: [String: Any] = [key: value]
            if key == "enabledKinds", let revision { single["kindsRevision"] = revision }
            if key == "aiProvider", let experimental { single["experimentalFeatures"] = experimental }
            guard let json = try? JSONSerialization.data(withJSONObject: single) else { return nil }
            return try? JSONDecoder().decode(Snapshot.self, from: json)
        }
    }

    private func save() {
        guard !loading, let data = try? JSONEncoder().encode(snapshot()) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Decodes to nil instead of failing, so one unreadable element doesn't fail the whole document.
public struct Lossy<Value: Codable>: Codable {
    public let value: Value?
    public init(value: Value?) { self.value = value }
    public init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}


import Foundation

/// Colours for the tile shown when a track has no artwork: a soft diagonal gradient whose hue is
/// seeded from the album (or title) and artist, so a record keeps its colour across launches.
/// Kept dark and muted enough that a white glyph on either stop stays at or above 3:1 contrast.
public enum ArtworkPlaceholder {
    public struct RGB: Equatable, Sendable {
        public let red: Double, green: Double, blue: Double
    }

    static let saturation = 0.42
    static let topBrightness = 0.50
    static let bottomBrightness = 0.34
    static let hueShift = 0.07

    /// The text that picks the hue: tracks from one album share a colour.
    public static func seed(title: String, artist: String, album: String) -> String {
        let record = album.isEmpty ? title : album
        return "\(artist.lowercased())|\(record.lowercased())"
    }

    /// Top-leading and bottom-trailing gradient stops for `seed`.
    public static func gradient(seed: String) -> [RGB] {
        let hue = Double(stableHash(seed) % 360) / 360
        return [
            rgb(hue: hue, saturation: saturation, brightness: topBrightness),
            rgb(hue: (hue + hueShift).truncatingRemainder(dividingBy: 1), saturation: saturation, brightness: bottomBrightness),
        ]
    }

    /// FNV-1a: `String.hashValue` is randomised per launch.
    static func stableHash(_ s: String) -> UInt64 {
        s.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }

    static func rgb(hue: Double, saturation s: Double, brightness v: Double) -> RGB {
        let h = hue * 6
        let sector = Int(h.rounded(.down)) % 6
        let f = h - h.rounded(.down)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch sector {
        case 0: return RGB(red: v, green: t, blue: p)
        case 1: return RGB(red: q, green: v, blue: p)
        case 2: return RGB(red: p, green: v, blue: t)
        case 3: return RGB(red: p, green: q, blue: v)
        case 4: return RGB(red: t, green: p, blue: v)
        default: return RGB(red: v, green: p, blue: q)
        }
    }

    /// WCAG contrast ratio of white text on `c`.
    public static func contrastWithWhite(_ c: RGB) -> Double {
        1.05 / (relativeLuminance(c) + 0.05)
    }

    static func relativeLuminance(_ c: RGB) -> Double {
        func linear(_ x: Double) -> Double { x <= 0.039_28 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }
}

import Foundation
@testable import IslandCore

@MainActor
func registerArtworkPlaceholderTests() {
    let S = "ArtworkPlaceholder"

    test(S, "white glyph keeps at least 3:1 contrast on every hue") {
        for hue in 0..<360 {
            for stop in [ArtworkPlaceholder.topBrightness, ArtworkPlaceholder.bottomBrightness] {
                let c = ArtworkPlaceholder.rgb(hue: Double(hue) / 360, saturation: ArtworkPlaceholder.saturation, brightness: stop)
                expect(ArtworkPlaceholder.contrastWithWhite(c) >= 3, "hue \(hue) contrast too low")
            }
        }
    }

    test(S, "gradient is stable for a seed and differs between seeds") {
        let a = ArtworkPlaceholder.gradient(seed: "artist|album")
        expectEqual(a, ArtworkPlaceholder.gradient(seed: "artist|album"))
        expectEqual(a.count, 2)
        expect(a != ArtworkPlaceholder.gradient(seed: "someone|else"))
    }

    test(S, "tracks from one album share a seed") {
        expectEqual(ArtworkPlaceholder.seed(title: "One", artist: "A", album: "LP"),
                    ArtworkPlaceholder.seed(title: "Two", artist: "a", album: "lp"))
        expect(ArtworkPlaceholder.seed(title: "One", artist: "A", album: "") != ArtworkPlaceholder.seed(title: "Two", artist: "A", album: ""))
    }

    test(S, "hsb conversion hits the primaries") {
        expectEqual(ArtworkPlaceholder.rgb(hue: 0, saturation: 1, brightness: 1), .init(red: 1, green: 0, blue: 0))
        expectEqual(ArtworkPlaceholder.rgb(hue: 1.0 / 3, saturation: 1, brightness: 1), .init(red: 0, green: 1, blue: 0))
        expectEqual(ArtworkPlaceholder.rgb(hue: 2.0 / 3, saturation: 1, brightness: 1), .init(red: 0, green: 0, blue: 1))
    }
}

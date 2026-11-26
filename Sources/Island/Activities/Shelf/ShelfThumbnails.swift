import AppKit
import QuickLookThumbnailing
import SwiftUI

/// QuickLook thumbnails for shelf tiles, generated off the main thread and cached in memory.
@MainActor
enum ShelfThumbnails {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        return c
    }()

    static func cached(for url: URL, pointSize: CGFloat, scale: CGFloat) -> NSImage? {
        cache.object(forKey: key(url, pointSize, scale))
    }

    /// The thumbnail, or nil when QuickLook can't make one (or the task was cancelled).
    static func load(for url: URL, pointSize: CGFloat, scale: CGFloat) async -> NSImage? {
        let cacheKey = key(url, pointSize, scale)
        if let hit = cache.object(forKey: cacheKey) { return hit }
        let size = CGSize(width: pointSize, height: pointSize)
        guard let cg = await generate(url: url, size: size, scale: scale), !Task.isCancelled else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    /// Wraps the callback API so cancelling the Swift task cancels the QuickLook request too.
    private static func generate(url: URL, size: CGSize, scale: CGFloat) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
        let generator = QLThumbnailGenerator.shared
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
                generator.generateBestRepresentation(for: request) { representation, _ in
                    continuation.resume(returning: representation?.cgImage)
                }
            }
        } onCancel: {
            generator.cancel(request)
        }
    }

    private static func key(_ url: URL, _ pointSize: CGFloat, _ scale: CGFloat) -> NSString {
        "\(url.path)|\(Int(pointSize * scale))" as NSString
    }
}

/// The tile image: the Finder icon at once, swapped for the QuickLook thumbnail when it arrives.
/// On failure the icon simply stays.
struct ShelfThumbnailImage: View {
    let url: URL
    let size: CGFloat
    @Environment(\.displayScale) private var scale
    @State private var thumbnail: NSImage?

    var body: some View {
        let image = thumbnail ?? ShelfThumbnails.cached(for: url, pointSize: size, scale: scale)
        Image(nsImage: image ?? ImageCache.fileIcon(path: url.path))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .task(id: TaskKey(url: url, scale: scale)) { await refresh() }
    }

    private func refresh() async {
        thumbnail = nil
        let loaded = await ShelfThumbnails.load(for: url, pointSize: size, scale: scale)
        // A newer task (different file or screen) owns the view now; drop this result.
        guard !Task.isCancelled, let loaded else { return }
        thumbnail = loaded
    }

    private struct TaskKey: Equatable {
        let url: URL
        let scale: CGFloat
    }
}

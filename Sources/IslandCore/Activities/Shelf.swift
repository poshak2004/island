import Foundation

/// A file parked on the Island. Holds a path, never the file's contents.
public struct ShelfItem: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let url: URL
    public let name: String

    public init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url.standardizedFileURL
        self.name = url.lastPathComponent
    }
}

public struct ShelfActivity: Equatable, Sendable {
    public var items: [ShelfItem]
    /// A file drag is in progress near the notch: the Island shows its drop targets.
    public var isDropTarget: Bool

    public init(items: [ShelfItem], isDropTarget: Bool = false) {
        self.items = items
        self.isDropTarget = isDropTarget
    }
}

public enum ShelfLogic {
    public static let maxItems = 24

    /// Appends new file URLs (skipping ones already on the shelf), keeping the newest `maxItems`.
    public static func adding(_ urls: [URL], to items: [ShelfItem]) -> [ShelfItem] {
        var seen = Set(items.map(\.url.path))
        var out = items
        for url in urls where url.isFileURL {
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            out.append(ShelfItem(url: url))
        }
        return Array(out.suffix(maxItems))
    }

    public static func removing(_ id: UUID, from items: [ShelfItem]) -> [ShelfItem] {
        items.filter { $0.id != id }
    }

    /// Drops items whose file no longer exists (deleted or moved since it was parked), keeping order.
    public static func keepingExisting(_ items: [ShelfItem], exists: (URL) -> Bool) -> [ShelfItem] {
        items.filter { exists($0.url) }
    }
}

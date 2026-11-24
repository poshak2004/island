import AppKit
import IslandCore
import SwiftUI
import UniformTypeIdentifiers

enum ShelfStyle {
    static let tint = Color(red: 0.55, green: 0.72, blue: 1.0)
    static let symbol = "tray.full.fill"
    static let tileWidth: CGFloat = 66

    static func label(_ s: ShelfActivity) -> String {
        s.items.count == 1 ? "1 file" : "\(s.items.count) files"
    }
}

// MARK: Compact / minimal

struct ShelfCompactLeading: View {
    let shelf: ShelfActivity
    var body: some View {
        Image(systemName: shelf.isDropTarget ? "tray.and.arrow.down.fill" : ShelfStyle.symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ShelfStyle.tint)
    }
}

struct ShelfCompactTrailing: View {
    let shelf: ShelfActivity
    var body: some View {
        CompactTrailingText(text: "\(shelf.items.count)", tint: ShelfStyle.tint)
    }
}

struct ShelfMinimal: View {
    let shelf: ShelfActivity
    var body: some View {
        Image(systemName: ShelfStyle.symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(ShelfStyle.tint)
    }
}

// MARK: Expanded

struct ShelfExpanded: View {
    let shelf: ShelfActivity
    @Environment(\.islandCommands) private var send

    var body: some View {
        VStack(spacing: 10) {
            if shelf.isDropTarget || shelf.items.isEmpty {
                HStack(spacing: 10) {
                    ShelfDropZone(title: "Keep on Shelf", symbol: "tray.and.arrow.down") { send(.shelf(.add($0))) }
                    ShelfDropZone(title: "AirDrop", symbol: "dot.radiowaves.left.and.right") { send(.shelf(.airDrop($0))) }
                }
                .frame(height: 76)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.items) { ShelfTile(item: $0) }
                    }
                }
                .frame(height: 76)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    ShelfDrop.load(providers) { send(.shelf(.add($0))) }
                    return true
                }
                HStack(spacing: 8) {
                    Text("\(ShelfStyle.label(shelf)) · drag out to use")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(IslandPalette.secondaryText)
                    Spacer(minLength: 0)
                    IslandPillButton(title: "AirDrop All", symbol: "dot.radiowaves.left.and.right", tint: ShelfStyle.tint) {
                        send(.shelf(.airDrop([])))
                    }
                    IslandPillButton(title: "Clear", symbol: nil, tint: .white) { send(.shelf(.clear)) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File shelf")
    }
}

private struct ShelfDropZone: View {
    let title: String
    let symbol: String
    let onDrop: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
            Text(title).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(targeted ? .black : .white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(targeted ? ShelfStyle.tint : .white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(.white.opacity(targeted ? 0 : 0.35)))
        .animation(.easeOut(duration: 0.15), value: targeted)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            ShelfDrop.load(providers, completion: onDrop)
            return true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop files to \(title)")
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    @Environment(\.islandCommands) private var send
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: ImageCache.fileIcon(path: item.url.path))
                .resizable()
                .frame(width: 38, height: 38)
            Text(item.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 3)
        }
        .frame(width: ShelfStyle.tileWidth, height: 76, alignment: .top)
        .padding(.top, 2)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering ? 0.1 : 0)))
        .overlay(FileDragSource(url: item.url))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { send(.shelf(.remove(item.id))) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(item.name)")
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open") { send(.openFile(item.url)) }
            Button("Show in Finder") { send(.revealFile(item.url)) }
            Button("AirDrop") { send(.shelf(.airDrop([item.url]))) }
            Divider()
            Button("Remove from Shelf") { send(.shelf(.remove(item.id))) }
        }
        .help(item.url.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityHint("Drag out to use. More options in the context menu.")
        .accessibilityAction(named: "Open") { send(.openFile(item.url)) }
        .accessibilityAction(named: "Remove") { send(.shelf(.remove(item.id))) }
    }
}

enum ShelfDrop {
    /// Resolves dropped item providers to file URLs, then calls back once on the main actor.
    static func load(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let found = urls
            MainActor.assumeIsolated { if !found.isEmpty { completion(found) } }
        }
    }
}

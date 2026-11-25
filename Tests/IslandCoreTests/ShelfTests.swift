import Foundation
@testable import IslandCore

@MainActor
func registerShelfTests() {
    let S = "Shelf"
    let a = URL(fileURLWithPath: "/tmp/a.pdf"), b = URL(fileURLWithPath: "/tmp/b.png")

    test(S, "adds file URLs in order and names them") {
        let items = ShelfLogic.adding([a, b], to: [])
        expectEqual(items.map(\.name), ["a.pdf", "b.png"])
    }

    test(S, "ignores duplicates (same file, different spelling) and non-file URLs") {
        var items = ShelfLogic.adding([a], to: [])
        items = ShelfLogic.adding([URL(fileURLWithPath: "/tmp/./a.pdf"), URL(string: "https://example.com")!], to: items)
        expectEqual(items.count, 1)
    }

    test(S, "keeps the newest items when over the limit") {
        let urls = (0..<(ShelfLogic.maxItems + 3)).map { URL(fileURLWithPath: "/tmp/f\($0)") }
        let items = ShelfLogic.adding(urls, to: [])
        expectEqual(items.count, ShelfLogic.maxItems)
        expectEqual(items.first?.name, "f3")
        expectEqual(items.last?.name, "f\(ShelfLogic.maxItems + 2)")
    }

    test(S, "removes by id and leaves the rest untouched") {
        let items = ShelfLogic.adding([a, b], to: [])
        let left = ShelfLogic.removing(items[0].id, from: items)
        expectEqual(left, [items[1]])
        expectEqual(ShelfLogic.removing(UUID(), from: items), items)
    }

    test(S, "keepingExisting drops items whose file is gone and keeps order") {
        let c = URL(fileURLWithPath: "/tmp/c.txt")
        let items = ShelfLogic.adding([a, b, c], to: [])
        let left = ShelfLogic.keepingExisting(items) { $0.path != b.path }
        expectEqual(left.map(\.name), ["a.pdf", "c.txt"])
        expectEqual(ShelfLogic.keepingExisting(items) { _ in true }, items)
        expect(ShelfLogic.keepingExisting(items) { _ in false }.isEmpty)
    }

    test(S, "validator accepts shelf content only for the shelf kind") {
        let content = ActivityContent.shelf(ShelfActivity(items: ShelfLogic.adding([a], to: [])))
        let manager = ActivityManager()
        manager.submit(.upsert(Activity(id: "shelf", kind: .media, priority: .low, content: content)))
        expect(manager.activity(id: "shelf") == nil)
        manager.submit(.upsert(Activity(id: "shelf", kind: .shelf, priority: .low, content: content)))
        expect(manager.activity(id: "shelf") != nil)
    }
}

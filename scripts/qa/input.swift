// QA input driver: synthesizes real mouse/keyboard events (needs Accessibility for the terminal).
// usage: input move X Y | click X Y | rclick X Y | drag X1 Y1 X2 Y2 STEPS MS [HOLD_MS] | key CODE | trusted | where
import AppKit
import ApplicationServices
let a = CommandLine.arguments
func flip(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) } // CG coords: origin top-left
// Scripts use coordinates relative to the notched display's top-left. When it isn't the main display,
// set ISLAND_QA_ORIGIN="x,y" (its CG origin) and every event and AX position is shifted accordingly.
let origin: CGPoint = {
    let parts = (ProcessInfo.processInfo.environment["ISLAND_QA_ORIGIN"] ?? "").split(separator: ",").compactMap { Double($0) }
    return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : .zero
}()
func O(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + origin.x, y: p.y + origin.y) }
switch a[1] {
case "trusted": print(AXIsProcessTrusted())
case "where": let p = CGEvent(source: nil)!.location; print(p.x - origin.x, p.y - origin.y)
case "move":
    let p = flip(Double(a[2])!, Double(a[3])!)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: O(p), mouseButton: .left)?.post(tap: .cghidEventTap)
case "glide": // glide X1 Y1 X2 Y2 STEPS MS
    let x1 = Double(a[2])!, y1 = Double(a[3])!, x2 = Double(a[4])!, y2 = Double(a[5])!, n = Int(a[6])!, ms = Double(a[7])!
    for i in 0...n {
        let t = Double(i) / Double(n)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: O(CGPoint(x: x1 + (x2 - x1) * t, y: y1 + (y2 - y1) * t)), mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(useconds_t(ms * 1000))
    }
case "drag": // drag X1 Y1 X2 Y2 STEPS MS HOLD_MS — press, drag, hover at the end, release
    let x1 = Double(a[2])!, y1 = Double(a[3])!, x2 = Double(a[4])!, y2 = Double(a[5])!, n = Int(a[6])!, ms = Double(a[7])!
    let hold = a.count > 8 ? Double(a[8])! : 600
    let start = CGPoint(x: x1, y: y1)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: O(start), mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(100_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: O(start), mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(150_000)
    for i in 1...n {
        let t = Double(i) / Double(n)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: O(CGPoint(x: x1 + (x2 - x1) * t, y: y1 + (y2 - y1) * t)), mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(useconds_t(ms * 1000))
    }
    let end = CGPoint(x: x2, y: y2)
    for _ in 0..<Int(hold / 50) { // keep wiggling so the drag session updates its target
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: O(end), mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(50_000)
    }
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: O(end), mouseButton: .left)?.post(tap: .cghidEventTap)
case "rclick":
    let p = flip(Double(a[2])!, Double(a[3])!)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: O(p), mouseButton: .right)?.post(tap: .cghidEventTap)
    usleep(30000)
    CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: O(p), mouseButton: .right)?.post(tap: .cghidEventTap)
    usleep(40000)
    CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: O(p), mouseButton: .right)?.post(tap: .cghidEventTap)
case "click":
    let p = flip(Double(a[2])!, Double(a[3])!)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: O(p), mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(30000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: O(p), mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(40000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: O(p), mouseButton: .left)?.post(tap: .cghidEventTap)
case "key":
    let code = CGKeyCode(a[2])!
    var flags: CGEventFlags = []
    if a.count > 3 { for c in a[3] { switch c { case "o": flags.insert(.maskAlternate); case "c": flags.insert(.maskCommand); case "s": flags.insert(.maskShift); case "t": flags.insert(.maskControl); default: break } } }
    let d = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true); d?.flags = flags; d?.post(tap: .cghidEventTap)
    usleep(30000)
    let u = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false); u?.flags = flags; u?.post(tap: .cghidEventTap)
case "type":
    for ch in a[2].utf16 {
        let d = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true); var c = ch; d?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c); d?.post(tap: .cghidEventTap)
        let u = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false); u?.post(tap: .cghidEventTap)
        usleep(20000)
    }
case "ax", "axdump":
    // ax LABEL → prints "x y" (CG coords) of the centre of the first Island element with that label.
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.poshak2004.island").first
        ?? NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "Island" }) else { print("no app"); exit(1) }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    func attr(_ e: AXUIElement, _ k: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, k as CFString, &v); return v }
    func label(_ e: AXUIElement) -> String {
        [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute].compactMap { attr(e, $0) as? String }.first { !$0.isEmpty } ?? ""
    }
    func frame(_ e: AXUIElement) -> CGRect? {
        guard let p = attr(e, kAXPositionAttribute), let s = attr(e, kAXSizeAttribute) else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt); AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }
    var found = false
    func walk(_ e: AXUIElement, _ depth: Int) {
        if found { return }
        let l = label(e), role = attr(e, kAXRoleAttribute) as? String ?? ""
        if a[1] == "axdump", !l.isEmpty || role == "AXButton" { print(String(repeating: " ", count: depth) + "\(role) “\(l)” \(frame(e).map { "\(Int($0.midX - origin.x)),\(Int($0.midY - origin.y)) \(Int($0.width))x\(Int($0.height))" } ?? "")") }
        if a[1] == "ax", l == a[2], let f = frame(e) { print(Int(f.midX - origin.x), Int(f.midY - origin.y)); found = true; return }
        for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(c, depth + 1) }
    }
    for w in (attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { walk(w, 0) }
    if a[1] == "ax", !found { print("notfound"); exit(2) }
default: break
}

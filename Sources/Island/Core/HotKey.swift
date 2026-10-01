import AppKit
import Carbon.HIToolbox
import Foundation
import IslandCore

/// System-wide shortcut via Carbon's RegisterEventHotKey — public, and needs no Accessibility permission.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private(set) var registered: IslandShortcut?
    private(set) var lastError: OSStatus = noErr

    init(action: @escaping () -> Void) { self.action = action }

    func register(_ shortcut: IslandShortcut?) {
        unregister()
        guard let shortcut else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
                guard let ctx else { return noErr }
                let hk = Unmanaged<HotKey>.fromOpaque(ctx).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { hk.action() } }
                return noErr
            }, 1, &spec, selfPtr, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x49534C44 /* ISLD */), id: 1)
        lastError = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        registered = lastError == noErr ? shortcut : nil
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        registered = nil
    }

    /// Converts AppKit modifier flags to Carbon's mask.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static func display(keyCode: UInt16, characters: String?, flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        let names: [UInt16: String] = [49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        return s + (names[keyCode] ?? (characters ?? "?").uppercased())
    }
}

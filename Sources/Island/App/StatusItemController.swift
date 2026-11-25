import AppKit
import IslandCore

/// Menu bar entry point (the app has no Dock icon).
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let env: AppEnvironment
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    init(env: AppEnvironment) {
        self.env = env
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Island")
            button.image?.isTemplate = true
        }
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let toggle = NSMenuItem(title: "Show Island", action: #selector(toggleIsland), keyEquivalent: "")
        toggle.state = env.settings.islandEnabled ? .on : .off
        toggle.target = self
        menu.addItem(toggle)
        let quiet = NSMenuItem(title: "Quiet Mode", action: #selector(toggleQuiet), keyEquivalent: "")
        quiet.state = env.settings.quietMode ? .on : .off
        quiet.target = self
        menu.addItem(quiet)
        if env.settings.searchEnabled, env.settings.islandEnabled {
            let s = NSMenuItem(title: "Search… (\(env.settings.searchShortcut.display))", action: #selector(openSearch), keyEquivalent: "")
            s.target = self
            menu.addItem(s)
        }
        if env.settings.islandEnabled, env.settings.enabledKinds.contains(.teleprompter) {
            let running = env.teleprompter.isActive
            add(running ? "Close Teleprompter" : "Start Teleprompter", #selector(toggleTeleprompter), key: "")
        }
        env.updates.checkIfDue() // at most once a day
        menu.addItem(.separator())
        if let update = env.updates.available {
            add("Update Available — \(update.version) (build \(update.build))…", #selector(openUpdate), key: "")
        }
        add("Settings…", #selector(openSettings), key: ",")
        #if DEBUG
        add("Debug Panel", #selector(openDebug), key: "d")
        #endif
        menu.addItem(.separator())
        add("Quit Island", #selector(quit), key: "q")
    }

    private func add(_ title: String, _ sel: Selector, key: String) {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        menu.addItem(i)
    }

    @objc private func toggleIsland() { env.settings.islandEnabled.toggle() }
    @objc private func toggleQuiet() { env.settings.quietMode.toggle() }
    @objc private func openSearch() {
        // Let the menu finish closing before the panel takes key focus.
        DispatchQueue.main.async { self.env.commands.perform(.ui(.toggleSearch)) }
    }
    @objc private func toggleTeleprompter() {
        if env.teleprompter.isActive { env.teleprompter.stop() } else { env.startTeleprompterFromSettings() }
    }
    @objc private func openSettings() { env.commands.perform(.openSettings) }
    @objc private func openUpdate() {
        if let page = env.updates.available?.page { NSWorkspace.shared.open(page) }
    }
    @objc private func openDebug() { env.showDebugPanel() }
    @objc private func quit() { NSApp.terminate(nil) }
}

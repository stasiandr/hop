import AppKit
import HopCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ConfigStore()
    private let hotKey = GlobalHotKey()
    private var panel: LauncherPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = LauncherPanel()
        hotKey.onPress = { [weak self] in self?.toggle() }
        applyConfig()

        // Launching hop again (e.g. from Finder) opens the panel.
        if CommandLine.arguments.contains("--show") { show() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }

    private func toggle() {
        panel.isVisible ? panel.dismiss() : show()
    }

    private func show() {
        if store.reloadIfChanged() { applyConfig() }
        panel.present()
    }

    private func applyConfig() {
        let config = store.config
        panel.apply(config: config, items: resolveItems(config) + builtins())
        panel.error = store.error

        if let problem = LoginAgentFile.sync(enabled: config.launchAtLogin) {
            panel.error = problem
        }

        do {
            let key = try Hotkey.parse(config.hotkey)
            if !hotKey.register(key) {
                panel.error = "Could not register hotkey \(config.hotkey) — is it taken by another app?"
            }
        } catch {
            panel.error = "\(error)"
        }
    }

    private func resolveItems(_ config: Config) -> [Item] {
        config.apps.compactMap { entry in
            let url: URL?
            if let path = entry.path {
                url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            } else {
                url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID!)
            }
            guard let url, FileManager.default.fileExists(atPath: url.path) else {
                NSLog("hop: skipping \(entry.name): app not found")
                return nil
            }
            return Item(
                title: entry.name,
                subtitle: url.path,
                terms: [entry.name] + entry.aliases,
                icon: NSWorkspace.shared.icon(forFile: url.path),
                run: { Self.open(app: url) }
            )
        }
    }

    /// Launches the app, or brings it to the front (reopening a window if it
    /// has none) when it's already running.
    private static func open(app url: URL) {
        if #available(macOS 14.0, *), let id = Bundle(url: url)?.bundleIdentifier {
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: id)
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, error in
            guard let error else { return }
            NSLog("hop: failed to open \(url.path): \(error)")
            DispatchQueue.main.async { NSApp.hide(nil) } // don't keep focus with no window
        }
    }

    /// Commands for hop itself. Only shown when the query matches them.
    private func builtins() -> [Item] {
        let gear = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        return [
            Item(title: "Edit hop config", subtitle: ConfigStore.url.path, terms: ["hop config", "edit config"],
                 icon: gear, hiddenWhenEmpty: true, run: { [store] in
                     store.ensureExists()
                     NSWorkspace.shared.open(ConfigStore.url)
                 }),
            Item(title: "Quit hop", subtitle: nil, terms: ["quit hop"],
                 icon: NSImage(systemSymbolName: "power", accessibilityDescription: nil),
                 hiddenWhenEmpty: true, run: { NSApp.terminate(nil) }),
        ]
    }
}

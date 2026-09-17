import AppKit
import HopCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ConfigStore()
    private let inventoryStore = InventoryStore()
    private let hotKey = GlobalHotKey()
    private var panel: LauncherPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = LauncherPanel()
        hotKey.onPress = { [weak self] in self?.toggle() }
        _ = inventoryStore.reloadIfChanged(path: store.config.inventory)
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
        let configChanged = store.reloadIfChanged()
        let inventoryChanged = inventoryStore.reloadIfChanged(path: store.config.inventory)
        if configChanged || inventoryChanged { applyConfig() }
        panel.present()
    }

    private func applyConfig() {
        let config = store.config
        let apps = resolveItems(config)
        let inventory = inventoryStore.inventory.excluding(config.exclude)
        panel.apply(config: config, items: apps + inventoryApps(inventory, skipping: apps) + projects(inventory, config) + unityProjects(inventory, config) + builtins())
        panel.error = store.error ?? inventoryStore.error

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
                subtitle: url.standardizedFileURL.path,
                terms: [entry.name] + entry.aliases,
                icon: Self.icon(atPath: url.path),
                run: { Self.open(app: url) }
            )
        }
    }

    /// Inventory apps not already listed as [[app]] (which may add aliases).
    private func inventoryApps(_ inventory: Inventory, skipping manual: [Item]) -> [Item] {
        let known = Set(manual.compactMap(\.subtitle))
        return inventory.apps.compactMap { app in
            let url = URL(fileURLWithPath: app.path).standardizedFileURL
            guard !known.contains(url.path), FileManager.default.fileExists(atPath: url.path) else { return nil }
            return Item(
                title: app.title,
                subtitle: url.path,
                terms: [app.title, app.name],
                icon: Self.icon(atPath: url.path),
                run: { Self.open(app: url) }
            )
        }
    }

    private func projects(_ inventory: Inventory, _ config: Config) -> [Item] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return inventory.tools.compactMap { tool in
            let url = URL(fileURLWithPath: tool.path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let shown = url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
            return Item(
                title: tool.name,
                subtitle: shown,
                terms: [tool.name],
                icon: Self.icon(atPath: url.path),
                run: { Self.open(folder: url, with: config.projectOpen ?? config.projectAltOpen) },
                altRun: { Self.open(folder: url, with: config.projectAltOpen ?? config.projectOpen) }
            )
        }
    }

    /// Return opens the project in Unity; ⌘Return uses `project.alt_open` like other projects.
    private func unityProjects(_ inventory: Inventory, _ config: Config) -> [Item] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let hub = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.unity3d.unityhub")
        return inventory.unity.compactMap { project in
            let url = URL(fileURLWithPath: project.path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let shown = url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
            return Item(
                title: project.name,
                subtitle: [project.version.map { "Unity \($0)" }, shown].compactMap { $0 }.joined(separator: " · "),
                terms: [project.name, "unity \(project.name)"],
                icon: Self.icon(atPath: hub?.path ?? url.path),
                run: { UnityLauncher.open(project: url.path) },
                altRun: { Self.open(folder: url, with: config.projectAltOpen ?? config.projectOpen) }
            )
        }
    }

    /// Icon of what the path points to: a symlink (e.g. ~/Applications/Pilot.app
    /// made by mac-and-conf) would otherwise get Finder's alias arrow.
    private static func icon(atPath path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
    }

    /// Opens a folder in the app with this bundle id, or in Finder.
    private static func open(folder: URL, with bundleID: String?) {
        guard let bundleID, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            if let bundleID { NSLog("hop: no app with bundle id \(bundleID)") }
            NSWorkspace.shared.open(folder)
            return
        }
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleID)
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: cfg) { _, error in
            guard let error else { return }
            NSLog("hop: failed to open \(folder.path) with \(bundleID): \(error)")
            DispatchQueue.main.async { NSApp.hide(nil) }
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

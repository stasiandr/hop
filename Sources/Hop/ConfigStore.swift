import Foundation
import HopCore

/// Loads `~/.config/hop/config.toml` and reloads it when its mtime changes.
final class ConfigStore {
    static var url: URL {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return base.appendingPathComponent("hop/config.toml")
    }

    private(set) var config = Config()
    /// Human-readable problem with the config file, if any. The previous valid
    /// config stays active while this is set.
    private(set) var error: String?
    private var loadedModified: Date?

    init() {
        ensureExists()
        _ = reloadIfChanged()
    }

    func ensureExists() {
        let url = Self.url
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Config.defaultText.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Returns true when the config was (re)read, successfully or not.
    func reloadIfChanged() -> Bool {
        let url = Self.url
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard modified != loadedModified || loadedModified == nil else { return false }
        loadedModified = modified

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            config = try Config.parse(text)
            error = nil
        } catch {
            self.error = "config.toml: \(error)"
            NSLog("hop: \(self.error!)")
        }
        return true
    }
}

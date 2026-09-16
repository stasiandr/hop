import Foundation
import HopCore

/// Reads the inventory file named in the config and reloads it when it changes.
final class InventoryStore {
    private(set) var inventory = Inventory()
    private(set) var error: String?
    private var loaded: (path: String, modified: Date?)?

    /// Returns true when the inventory was (re)read or dropped.
    func reloadIfChanged(path: String?) -> Bool {
        guard let path else {
            defer { loaded = nil; inventory = Inventory(); error = nil }
            return loaded != nil
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).resolvingSymlinksInPath()
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let loaded, loaded.path == url.path, loaded.modified == modified { return false }
        loaded = (url.path, modified)

        // Not written yet (e.g. before the first `mac-and-conf apply`): just empty.
        guard modified != nil else {
            inventory = Inventory()
            error = nil
            return true
        }
        do {
            inventory = try Inventory.parse(Data(contentsOf: url))
            error = nil
        } catch {
            self.error = "inventory: \(error.localizedDescription)"
            NSLog("hop: \(self.error!)")
        }
        return true
    }
}

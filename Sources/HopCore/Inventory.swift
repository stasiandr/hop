import Foundation

/// Apps and projects from an external inventory file, such as the one
/// `mac-and-conf apply` writes to `~/.local/state/mac-and-conf/inventory.json`.
public struct Inventory: Codable, Equatable, Sendable {
    public struct App: Codable, Equatable, Sendable {
        /// Identifier used by `exclude` (for mac-and-conf: the cask name).
        public var name: String
        public var path: String
    }

    public struct Tool: Codable, Equatable, Sendable {
        public var name: String
        public var path: String
    }

    public var apps: [App] = []
    public var tools: [Tool] = []

    public init(apps: [App] = [], tools: [Tool] = []) {
        self.apps = apps
        self.tools = tools
    }

    public static func parse(_ data: Data) throws -> Inventory {
        try JSONDecoder().decode(Inventory.self, from: data)
    }

    /// Drops everything whose name is listed in `exclude` (case-insensitive).
    public func excluding(_ exclude: [String]) -> Inventory {
        let names = Set(exclude.map { $0.lowercased() })
        return Inventory(
            apps: apps.filter { !names.contains($0.name.lowercased()) },
            tools: tools.filter { !names.contains($0.name.lowercased()) }
        )
    }
}

extension Inventory.App {
    /// "/Applications/Unity Hub.app" → "Unity Hub".
    public var title: String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}

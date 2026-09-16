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

    /// Unity projects: opened in the Unity editor they were made with.
    public struct UnityProject: Codable, Equatable, Sendable {
        public var name: String
        public var path: String
        /// From `ProjectSettings/ProjectVersion.txt`, e.g. `6000.3.24f1`.
        public var version: String?

        public init(name: String, path: String, version: String? = nil) {
            self.name = name
            self.path = path
            self.version = version
        }
    }

    public var apps: [App] = []
    public var tools: [Tool] = []
    public var unity: [UnityProject] = []

    public init(apps: [App] = [], tools: [Tool] = [], unity: [UnityProject] = []) {
        self.apps = apps
        self.tools = tools
        self.unity = unity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apps = try c.decodeIfPresent([App].self, forKey: .apps) ?? []
        tools = try c.decodeIfPresent([Tool].self, forKey: .tools) ?? []
        unity = try c.decodeIfPresent([UnityProject].self, forKey: .unity) ?? []
    }

    public static func parse(_ data: Data) throws -> Inventory {
        try JSONDecoder().decode(Inventory.self, from: data)
    }

    /// Drops everything whose name is listed in `exclude` (case-insensitive).
    public func excluding(_ exclude: [String]) -> Inventory {
        let names = Set(exclude.map { $0.lowercased() })
        return Inventory(
            apps: apps.filter { !names.contains($0.name.lowercased()) },
            tools: tools.filter { !names.contains($0.name.lowercased()) },
            unity: unity.filter { !names.contains($0.name.lowercased()) }
        )
    }
}

extension Inventory.App {
    /// "/Applications/Unity Hub.app" → "Unity Hub".
    public var title: String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}

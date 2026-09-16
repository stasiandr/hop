import Foundation

public struct AppEntry: Equatable, Sendable {
    /// Display name; falls back to the bundle file name.
    public var name: String
    /// Path to the .app bundle (`~` is expanded). Either this or `bundleID` is set.
    public var path: String?
    public var bundleID: String?
    /// Extra search terms, e.g. `["web", "browser"]`.
    public var aliases: [String]

    public init(name: String, path: String? = nil, bundleID: String? = nil, aliases: [String] = []) {
        self.name = name
        self.path = path
        self.bundleID = bundleID
        self.aliases = aliases
    }
}

public struct Config: Equatable, Sendable {
    public var hotkey: String = "alt+space"
    public var width: Double = 640
    public var maxResults: Int = 8
    public var apps: [AppEntry] = []

    public init() {}

    public static func parse(_ text: String) throws -> Config {
        let root = try TOML.parse(text)
        var config = Config()

        if let v = root["hotkey"] {
            guard let s = v.string else { throw ConfigError("hotkey must be a string") }
            _ = try Hotkey.parse(s)
            config.hotkey = s
        }
        if let v = root["width"] {
            guard let d = v.double, d >= 200 else { throw ConfigError("width must be a number >= 200") }
            config.width = d
        }
        if let v = root["max_results"] {
            guard let i = v.int, i >= 1 else { throw ConfigError("max_results must be an integer >= 1") }
            config.maxResults = i
        }

        if let v = root["app"] {
            guard let items = v.array else { throw ConfigError("use [[app]] to declare apps") }
            config.apps = try items.enumerated().map { index, item in
                try parseApp(item.table ?? [:], index: index)
            }
        }
        return config
    }

    private static func parseApp(_ t: [String: TOMLValue], index: Int) throws -> AppEntry {
        let label = "app #\(index + 1)"
        func string(_ key: String) throws -> String? {
            guard let v = t[key] else { return nil }
            guard let s = v.string, !s.isEmpty else { throw ConfigError("\(label): \(key) must be a non-empty string") }
            return s
        }

        let path = try string("path")
        let bundleID = try string("bundle")
        guard (path == nil) != (bundleID == nil) else {
            throw ConfigError("\(label): set exactly one of `path` or `bundle`")
        }

        var aliases: [String] = []
        if let v = t["alias"] {
            switch v {
            case .string(let s): aliases = [s]
            case .array(let items):
                aliases = try items.map {
                    guard let s = $0.string else { throw ConfigError("\(label): alias must be strings") }
                    return s
                }
            default: throw ConfigError("\(label): alias must be a string or array of strings")
            }
        }

        let fallbackName = path.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? bundleID!
        let name = try string("name") ?? fallbackName
        return AppEntry(name: name, path: path, bundleID: bundleID, aliases: aliases)
    }

    public static let defaultText = """
    # hop configuration. Changes are picked up the next time the panel opens.

    # Global shortcut. Modifiers: cmd, alt (opt), ctrl, shift.
    hotkey = "alt+space"

    # Panel width in points and how many results to show.
    width = 640
    max_results = 8

    # Each [[app]] is something hop can launch.
    #   path   — path to the .app bundle (~ allowed), or
    #   bundle — bundle identifier (e.g. "com.apple.Safari")
    #   name   — optional display name
    #   alias  — optional extra search terms

    [[app]]
    path = "/System/Applications/Utilities/Terminal.app"
    alias = ["term", "shell"]

    [[app]]
    bundle = "com.apple.finder"
    name = "Finder"

    [[app]]
    path = "/System/Applications/System Settings.app"
    alias = ["prefs", "settings"]

    """
}

public struct ConfigError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

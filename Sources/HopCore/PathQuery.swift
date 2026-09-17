import Foundation

/// Queries that are file system paths (`~/notes/index.json`, `/etc/hosts`):
/// the path itself when it exists, and entries of its folder that complete
/// the last component, so a path can be typed a few letters at a time.
public enum PathQuery {
    public struct Match: Equatable, Sendable {
        public var path: String
        public var isDirectory: Bool
    }

    /// The absolute path a query spells, or nil if it doesn't look like a path.
    public static func expand(_ query: String, home: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q == "~" { return home }
        if q.hasPrefix("~/") { return home + q.dropFirst() }
        if q.hasPrefix("/") { return q }
        return nil
    }

    /// `~/personal/ho` → `~/personal/hop` (exact match first), `~/personal/` →
    /// what's in it. Names compare ignoring case; hidden entries only show when
    /// the typed prefix starts with a dot.
    public static func matches(_ query: String, home: String, limit: Int,
                               fileManager: FileManager = .default) -> [Match] {
        guard limit > 0, let path = expand(query, home: home) else { return [] }
        var results: [Match] = []
        var isDir: ObjCBool = false
        let endsWithSlash = path.hasSuffix("/") && path != "/"
        let exact = endsWithSlash ? String(path.dropLast()) : path
        let last = (exact as NSString).lastPathComponent
        if last != ".", last != "..", fileManager.fileExists(atPath: exact, isDirectory: &isDir) {
            results.append(Match(path: exact, isDirectory: isDir.boolValue))
        }

        let folder: String, prefix: String
        if path.hasSuffix("/") {
            folder = path
            prefix = ""
        } else {
            let slash = path.lastIndex(of: "/")!
            folder = String(path[...slash])
            prefix = String(path[path.index(after: slash)...])
        }
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder) else { return results }
        let shown = names
            .filter { prefix.hasPrefix(".") || !$0.hasPrefix(".") }
            .filter { $0.lowercased().hasPrefix(prefix.lowercased()) && $0 != prefix }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for name in shown.prefix(limit - results.count) {
            let child = folder + name
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: child, isDirectory: &isDir) else { continue }
            results.append(Match(path: child, isDirectory: isDir.boolValue))
        }
        return results
    }

    /// `/Users/me/x` → `~/x`.
    public static func abbreviate(_ path: String, home: String) -> String {
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

import Foundation

/// The checked-out branch of a git working tree, read straight from `HEAD`
/// so it's cheap enough to do every time a project is shown.
public enum GitBranch {
    /// "main", a short commit hash when HEAD is detached, or nil when the
    /// folder isn't a git working tree. Follows `.git` files (worktrees, submodules).
    public static func current(in folder: URL) -> String? {
        let dotGit = folder.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir) else { return nil }

        var gitDir = dotGit
        if !isDir.boolValue {
            guard let text = try? String(contentsOf: dotGit, encoding: .utf8),
                  let line = text.split(whereSeparator: \.isNewline).first,
                  line.hasPrefix("gitdir:") else { return nil }
            let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            gitDir = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: folder.path, isDirectory: true)).standardizedFileURL
        }
        guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
        return parse(head: head)
    }

    /// "ref: refs/heads/feature/x" → "feature/x"; a bare hash → its first 7 characters.
    public static func parse(head: String) -> String? {
        let head = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("ref:") {
            let ref = head.dropFirst("ref:".count).trimmingCharacters(in: .whitespaces)
            return ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
        }
        guard head.count >= 7, head.allSatisfy(\.isHexDigit) else { return nil }
        return String(head.prefix(7))
    }
}

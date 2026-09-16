import Foundation
import HopCore

/// Keeps `~/Library/LaunchAgents/dev.hop.launcher.plist` in line with `launch_at_login`.
enum LoginAgentFile {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(LoginAgent.label).plist")
    }

    /// Returns a problem to show, or nil. The agent takes effect at the next
    /// login; it isn't loaded now because hop is already running.
    static func sync(enabled: Bool) -> String? {
        let fm = FileManager.default
        do {
            if enabled {
                guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
                    return "launch_at_login: can't find hop's executable"
                }
                let text = LoginAgent.plist(executable: exe)
                if (try? String(contentsOf: url, encoding: .utf8)) == text { return nil }
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
            } else if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            return nil
        } catch {
            return "launch_at_login: \(error.localizedDescription)"
        }
    }
}

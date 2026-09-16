import Foundation

/// Start-at-login via a user LaunchAgent. A LaunchAgent (rather than
/// SMAppService) lets hop point at a path that survives `brew upgrade`.
public enum LoginAgent {
    public static let label = "dev.hop.launcher"

    /// Homebrew installs into `…/Cellar/hop/<version>/`, which disappears on
    /// upgrade; `…/opt/hop/` always points at the current version.
    public static func stablePath(_ path: String) -> String {
        guard let cellar = path.range(of: "/Cellar/hop/") else { return path }
        let rest = path[cellar.upperBound...]
        guard let slash = rest.firstIndex(of: "/") else { return path }
        return path[..<cellar.lowerBound] + "/opt/hop" + rest[slash...]
    }

    public static func plist(executable: String) -> String {
        let escaped = executable
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>ProgramArguments</key><array><string>\(escaped)</string></array>
            <key>RunAtLoad</key><true/>
            <key>LimitLoadToSessionType</key><string>Aqua</string>
            <key>ProcessType</key><string>Interactive</string>
        </dict>
        </plist>

        """
    }
}

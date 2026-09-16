import AppKit

/// Opens Unity projects: brings the editor that already has the project open to
/// the front, otherwise starts the right editor through the `unity` CLI. When
/// that fails (usually the editor version isn't installed), hands the project to
/// uhub, which offers to install it.
enum UnityLauncher {
    static func open(project path: String) {
        if let editor = runningEditor(for: path) {
            if #available(macOS 14.0, *), let id = editor.bundleIdentifier {
                NSApp.yieldActivation(toApplicationWithBundleIdentifier: id)
            }
            editor.activate()
            return
        }
        guard let cli else {
            fallback(path, reason: "unity CLI not found")
            return
        }
        let process = Process()
        process.executableURL = cli
        process.arguments = ["open", path]
        var env = ProcessInfo.processInfo.environment
        env["UNITY_NON_INTERACTIVE"] = "1"
        env["UNITY_NO_BANNER"] = "1"
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { process in
            guard process.terminationStatus != 0 else { return }
            DispatchQueue.main.async { fallback(path, reason: "unity open exited with \(process.terminationStatus)") }
        }
        do {
            try process.run()
        } catch {
            fallback(path, reason: "\(error)")
        }
    }

    private static var cli: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [String] = []
        let record = home.appendingPathComponent("Library/Application Support/UnityHub/cli-install.json")
        if let data = try? Data(contentsOf: record),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let path = object["path"] as? String {
            candidates.append(path)
        }
        candidates += [home.appendingPathComponent(".unity/bin/unity").path, "/opt/homebrew/bin/unity", "/usr/local/bin/unity"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    private static func fallback(_ path: String, reason: String) {
        NSLog("hop: can't open Unity project \(path): \(reason)")
        var components = URLComponents()
        components.scheme = "uhub"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        if let url = components.url, NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    /// A running Unity editor whose `-projectPath` argument is this project.
    private static func runningEditor(for path: String) -> NSRunningApplication? {
        let wanted = normalized(path)
        return NSWorkspace.shared.runningApplications.first { app in
            guard app.executableURL?.path.hasSuffix("/Contents/MacOS/Unity") == true else { return false }
            let args = arguments(of: app.processIdentifier)
            guard let flag = args.firstIndex(where: { $0.lowercased() == "-projectpath" }), flag + 1 < args.count else {
                return false
            }
            return normalized(args[flag + 1]) == wanted
        }
    }

    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
    }

    /// argv of another process of the same user, via KERN_PROCARGS2.
    private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argmax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&mib, 2, &argmax, &size, nil, 0) == 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: Int(argmax))
        mib = [CTL_KERN, KERN_PROCARGS2, pid]
        size = Int(argmax)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 } // executable path
        while index < size, buffer[index] == 0 { index += 1 } // padding
        var args: [String] = []
        while index < size, args.count < argc {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            args.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return args
    }
}

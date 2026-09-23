import Foundation
import Testing
@testable import HopCore

@Suite struct TOMLTests {
    @Test func scalarsTablesAndArrays() throws {
        let doc = try TOML.parse("""
        # comment
        title = "hop # not a comment"
        n = 1_000
        f = 1.5
        on = true
        lit = 'C:\\path'
        list = [
          "a", # trailing
          "b",
        ]

        [ui]
        width = 600

        [[app]]
        path = "/A.app"

        [[app]]
        path = "/B.app"
        alias = ["b"]
        """)
        #expect(doc["title"] == .string("hop # not a comment"))
        #expect(doc["n"] == .integer(1000))
        #expect(doc["f"] == .float(1.5))
        #expect(doc["on"] == .bool(true))
        #expect(doc["lit"] == .string("C:\\path"))
        #expect(doc["list"] == .array([.string("a"), .string("b")]))
        #expect(doc["ui"]?.table?["width"] == .integer(600))
        #expect(doc["app"]?.array?.count == 2)
        #expect(doc["app"]?.array?[1].table?["alias"] == .array([.string("b")]))
    }

    @Test func escapes() throws {
        let doc = try TOML.parse(#"s = "a\"b\n\u00e9""#)
        #expect(doc["s"] == .string("a\"b\né"))
    }

    @Test func errorsReportLine() {
        #expect(throws: TOMLError(line: 2, message: "duplicate key 'a'")) {
            try TOML.parse("a = 1\na = 2")
        }
        #expect(throws: TOMLError.self) { try TOML.parse("a = \"open") }
        #expect(throws: TOMLError.self) { try TOML.parse("just words") }
    }
}

@Suite struct ConfigTests {
    @Test func defaultTextParses() throws {
        let config = try Config.parse(Config.defaultText)
        #expect(config.hotkey == "alt+space")
        #expect(config.apps.count == 3)
        #expect(config.apps[0].name == "Terminal")
        #expect(config.apps[0].aliases == ["term", "shell"])
        #expect(config.apps[1].bundleID == "com.apple.finder")
    }

    @Test func emptyConfigUsesDefaults() throws {
        #expect(try Config.parse("") == Config())
    }

    @Test func singleAliasString() throws {
        let config = try Config.parse("[[app]]\npath = \"~/Apps/Foo Bar.app\"\nalias = \"fb\"")
        #expect(config.apps == [AppEntry(name: "Foo Bar", path: "~/Apps/Foo Bar.app", aliases: ["fb"])])
    }

    @Test func rejectsInvalid() {
        #expect(throws: ConfigError.self) { try Config.parse("[[app]]\nname = \"x\"") }
        #expect(throws: ConfigError.self) { try Config.parse("[[app]]\npath = \"/a\"\nbundle = \"b\"") }
        #expect(throws: ConfigError.self) { try Config.parse("hotkey = \"hyper+space\"") }
        #expect(throws: ConfigError.self) { try Config.parse("max_results = 0") }
    }
}

@Suite struct HotkeyTests {
    @Test func parses() throws {
        #expect(try Hotkey.parse("alt+space") == Hotkey(keyCode: 49, modifiers: Hotkey.option))
        #expect(try Hotkey.parse("Cmd + Shift + K") == Hotkey(keyCode: 40, modifiers: Hotkey.cmd | Hotkey.shift))
        #expect(try Hotkey.parse("f5") == Hotkey(keyCode: 96, modifiers: 0))
    }

    @Test func rejects() {
        #expect(throws: ConfigError.self) { try Hotkey.parse("space") }
        #expect(throws: ConfigError.self) { try Hotkey.parse("cmd+nope") }
        #expect(throws: ConfigError.self) { try Hotkey.parse("") }
    }
}

@Suite struct MatcherTests {
    @Test func basics() {
        #expect(Matcher.score("saf", "Safari") != nil)
        #expect(Matcher.score("sfr", "Safari") != nil)
        #expect(Matcher.score("xyz", "Safari") == nil)
        #expect(Matcher.score("", "Safari") == 0)
    }

    @Test func ranking() {
        let names = ["System Settings", "Safari", "Slack", "Screenshot"]
        #expect(Matcher.rank(names, query: "sa", terms: { [$0] }).first == "Safari")
        #expect(Matcher.rank(names, query: "ss", terms: { [$0] }).first == "System Settings")
        #expect(Matcher.rank(names, query: "", terms: { [$0] }) == names)
    }

    @Test func aliasesCount() {
        let items = [("Visual Studio Code", ["code"]), ("Xcode", [])]
        let ranked = Matcher.rank(items, query: "code", terms: { [$0.0] + $0.1 })
        #expect(ranked.first?.0 == "Visual Studio Code")
    }
}

@Suite struct LoginAgentTests {
    @Test func plistIsValid() throws {
        let text = LoginAgent.plist(executable: "/Apps/A&B/hop")
        let data = try #require(text.data(using: .utf8))
        let dict = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(dict["Label"] as? String == "dev.hop.launcher")
        #expect(dict["ProgramArguments"] as? [String] == ["/Apps/A&B/hop"])
        #expect(dict["RunAtLoad"] as? Bool == true)
    }

    @Test func configFlag() throws {
        #expect(try Config.parse("launch_at_login = true").launchAtLogin)
        #expect(throws: ConfigError.self) { try Config.parse("launch_at_login = 1") }
    }
}

@Suite struct GitBranchTests {
    @Test func parsesHead() {
        #expect(GitBranch.parse(head: "ref: refs/heads/main\n") == "main")
        #expect(GitBranch.parse(head: "ref: refs/heads/feature/x") == "feature/x")
        #expect(GitBranch.parse(head: "3702d36a1b2c3d4e5f60718293a4b5c6d7e8f901\n") == "3702d36")
        #expect(GitBranch.parse(head: "") == nil)
    }

    @Test func readsRepoAndWorktree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git/worktrees/wt"), withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(to: repo.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        try "ref: refs/heads/fix\n".write(to: repo.appendingPathComponent(".git/worktrees/wt/HEAD"), atomically: true, encoding: .utf8)
        let wt = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: wt, withIntermediateDirectories: true)
        try "gitdir: ../repo/.git/worktrees/wt\n".write(to: wt.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        #expect(GitBranch.current(in: repo) == "main")
        #expect(GitBranch.current(in: wt) == "fix")
        #expect(GitBranch.current(in: root) == nil)
    }
}

@Suite struct PathQueryTests {
    @Test func expandsOnlyPaths() {
        #expect(PathQuery.expand("~/a/index.json", home: "/Users/me") == "/Users/me/a/index.json")
        #expect(PathQuery.expand("~", home: "/Users/me") == "/Users/me")
        #expect(PathQuery.expand("/etc/hosts", home: "/Users/me") == "/etc/hosts")
        #expect(PathQuery.expand("safari", home: "/Users/me") == nil)
        #expect(PathQuery.expand("~user", home: "/Users/me") == nil)
        #expect(PathQuery.abbreviate("/Users/me/a", home: "/Users/me") == "~/a")
        #expect(PathQuery.abbreviate("/Users/mex", home: "/Users/me") == "/Users/mex")
    }

    @Test func completesFromDisk() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: home) }
        try FileManager.default.createDirectory(atPath: home + "/proj/src", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: home + "/project2", withIntermediateDirectories: true)
        for file in ["/proj/index.json", "/proj/.env", "/Proxy.txt"] {
            try "{}".write(toFile: home + file, atomically: true, encoding: .utf8)
        }
        func paths(_ q: String, limit: Int = 8) -> [String] {
            PathQuery.matches(q, home: home, limit: limit).map { PathQuery.abbreviate($0.path, home: home) }
        }

        #expect(PathQuery.matches("~/proj/index.json", home: home, limit: 8)
            == [.init(path: home + "/proj/index.json", isDirectory: false)])
        #expect(paths("~/proj") == ["~/proj", "~/project2"])
        #expect(paths("~/pro") == ["~/proj", "~/project2", "~/Proxy.txt"])
        #expect(paths("~/proj/") == ["~/proj", "~/proj/index.json", "~/proj/src"])
        #expect(paths("~/proj/.") == ["~/proj/.env"])
        #expect(paths("~/pro", limit: 2) == ["~/proj", "~/project2"])
        #expect(paths("~/nope/x").isEmpty)
        #expect(paths("hop").isEmpty)
    }
}

@Suite struct InventoryTests {
    @Test func parsesMacAndConfInventory() throws {
        let json = """
        {"apps": [{"name": "arc", "path": "/Applications/Arc.app"},
                  {"name": "unity-hub", "path": "/Applications/Unity Hub.app"}],
         "tools": [{"name": "hop", "path": "/Users/me/personal/hop", "repo": "git@github.com:me/hop.git"}]}
        """
        let inventory = try Inventory.parse(Data(json.utf8)).excluding(["Unity-Hub"])
        #expect(inventory.apps.map(\.title) == ["Arc"])
        #expect(inventory.tools == [Inventory.Tool(name: "hop", path: "/Users/me/personal/hop")])
    }

    @Test func parsesUnityProjects() throws {
        let json = """
        {"apps": [], "tools": [],
         "unity": [{"name": "dacha", "path": "/Users/me/work/dacha", "repo": "git@github.com:me/dacha.git", "version": "6000.3.24f1"},
                   {"name": "old", "path": "/Users/me/work/old", "repo": "r", "version": null}]}
        """
        let inventory = try Inventory.parse(Data(json.utf8)).excluding(["old"])
        #expect(inventory.unity == [Inventory.UnityProject(name: "dacha", path: "/Users/me/work/dacha", version: "6000.3.24f1")])
        // Inventories written before Unity support have no `unity` key.
        #expect(try Inventory.parse(Data(#"{"apps": [], "tools": []}"#.utf8)).unity.isEmpty)
    }

    @Test func configKeys() throws {
        let config = try Config.parse("""
        inventory = "~/.local/state/mac-and-conf/inventory.json"
        exclude = ["steam"]

        [project]
        open = "dev.zed.Zed"
        alt_open = "com.mitchellh.ghostty"
        """)
        #expect(config.inventory == "~/.local/state/mac-and-conf/inventory.json")
        #expect(config.exclude == ["steam"])
        #expect(config.projectOpen == "dev.zed.Zed")
        #expect(config.projectAltOpen == "com.mitchellh.ghostty")
        #expect(try Config.parse("currencies = [\"rub\", \"EUR\"]").currencies == ["RUB", "EUR"])
        #expect(throws: ConfigError.self) { try Config.parse("currencies = \"RUB\"") }
        #expect(throws: ConfigError.self) { try Config.parse("exclude = [1]") }
        #expect(throws: ConfigError.self) { try Config.parse("[project]\nopen_with = \"x\"") }
        #expect(throws: ConfigError.self) { try Config.parse("hot_key = \"alt+space\"") }
    }
}

@Suite struct CalculatorTests {
    private func texts(_ query: String) -> [String] { Calculator.evaluate(query).map(\.text) }
    private func first(_ query: String) -> String? { texts(query).first }

    @Test func arithmetic() {
        #expect(first("2 + 2 * 2") == "6")
        #expect(first("(2 + 2) * 2") == "8")
        #expect(first("2^10") == "1024")
        #expect(first("-2^2") == "-4")
        #expect(first("2^3^2") == "512")
        #expect(first("0.1 + 0.2") == "0.3")
        #expect(first("1/3") == "0.3333333333")
        #expect(first("10 mod 3") == "1")
        #expect(first("sqrt(16) + 1") == "5")
        #expect(first("2 * pi") == "6.283185307")
        #expect(first("sin(90 deg)") == "1")
        #expect(first("(1 + 2") == "3")
        #expect(first("2 + 2 =") == "4")
        #expect(first("2^20") == "1\u{202F}048\u{202F}576")
        #expect(Calculator.evaluate("2^20").first?.value == "1048576")
        #expect(first("0xff") == "255")
        #expect(first("1e3 * 2") == "2000")
        #expect(first("1 / 100000") == "0.00001")
        #expect(first("1 / 3 / 10000") == "0.00003333333333")
        #expect(first("1e-20 * 2") == "2e-20")
    }

    @Test func percents() {
        #expect(first("200 + 15%") == "230")
        #expect(first("200 - 10%") == "180")
        #expect(first("15% of 80") == "12")
        #expect(first("50 * 10%") == "5")
    }

    @Test func conversions() {
        #expect(first("90 min to h") == "1.5 h")
        #expect(first("3 h in s") == "10\u{202F}800 s")
        #expect(first("1.5 GB in MB") == "1500 MB")
        #expect(first("1 GiB to MB") == "1073.741824 MB")
        #expect(first("1024 kib to mib") == "1 MiB")
        #expect(first("100 Mbit to MB") == "12.5 MB")
        #expect(first("1 Gbps to MB/s") == "125 MB/s")
        #expect(first("12 in to cm") == "30.48 cm")
        #expect(first("5 ft in in") == "60 in")
        #expect(first("100 km/h to m/s") == "27.77777778 m/s")
        #expect(first("100 F to C") == "37.77777778 °C")
        #expect(first("-40 c -> f") == "-40 °F")
        #expect(first("1h 30min to min") == "90 min")
        #expect(first("255 to hex") == "0xff")
        #expect(first("10 to bin") == "0b1010")
        #expect(first("2 m^2 to cm^2") == "20\u{202F}000 cm²")
        #expect(texts("5 kg to s").isEmpty)
    }

    @Test func unitArithmetic() {
        #expect(first("100 km / 2 h") == "50 km/h")
        #expect(first("1 GB / 10 MB/s") == "100 s")
        #expect(first("1 GB / 1 MB") == "1000")
        #expect(first("5 min + 30 s") == "5.5 min")
        #expect(first("100 Mbps * 10 s") == "125\u{202F}000\u{202F}000 B")
        #expect(texts("5 min + 3").isEmpty)
    }

    @Test func humanizes() {
        #expect(texts("5400 s") == ["1.5 h", "1 h 30 min"])
        #expect(texts("1500000000 bytes") == ["1.5 GB", "1.397 GiB"])
        #expect(texts("1.5 GB") == ["1.397 GiB"])
        #expect(texts("10 MB * 1000") == ["10\u{202F}000 MB", "10 GB", "9.313 GiB"])
    }

    @Test func ignoresNonCalculations() {
        for query in ["", "safari", "42", "5 min", "pi", "1password", "7zip", "4k video", "Final Cut 2", "12 in"] {
            #expect(texts(query).isEmpty, "\(query)")
        }
    }
}

@Suite struct CurrencyTests {
    private let currencies: Currencies = {
        let json = #"{"date": "2026-09-17", "usd": {"usd": 1, "eur": 0.8, "rub": 80, "gel": 2.5, "btc": 0.00001, "one": 40, "ton": 0.3}}"#
        var c = try! Currencies.parse(Data(json.utf8))
        c.targets = ["GEL", "EUR"]
        return c
    }()

    private func texts(_ query: String) -> [String] {
        Calculator.evaluate(query, currencies: currencies).map(\.text)
    }

    @Test func parsesKnownCodesOnly() {
        #expect(Set(currencies.perDollar.keys) == ["USD", "EUR", "RUB", "GEL", "BTC"])
        #expect(currencies.date == "2026-09-17")
    }

    @Test func converts() {
        #expect(texts("100 usd to rub") == ["8000 RUB"])
        #expect(texts("$100 in eur") == ["80 EUR"])
        #expect(texts("10€ to $") == ["12.5 USD"])
        #expect(texts("1000 rub to usd") == ["12.5 USD"])
        #expect(texts("100 rubles to euros") == ["1 EUR"])
        #expect(texts("1 usd to btc") == ["0.00001 BTC"])
        #expect(texts("10 usd + 8 eur to rub") == ["1600 RUB"])
        #expect(texts("100 usd to rub").first.flatMap { _ in
            Calculator.evaluate("100 usd to rub", currencies: currencies).first?.note } == "rates of 2026-09-17")
    }

    @Test func showsTargetsWithoutTo() {
        #expect(texts("$100") == ["250 GEL", "80 EUR"])
        #expect(texts("100 gel") == ["32 EUR"])
        #expect(texts("$20 + 15%") == ["23 USD", "57.5 GEL", "18.4 EUR"])
        #expect(texts("1 usd / 3") == ["0.33 USD", "0.83 GEL", "0.27 EUR"])
    }

    @Test func staysOutOfTheWay() {
        #expect(texts("2 t to kg") == ["2000 kg"]) // tonnes, not a currency
        #expect(texts("top 10").isEmpty)
        #expect(texts("5 usd to kg").isEmpty)
        #expect(Calculator.evaluate("100 usd to rub").isEmpty) // no rates yet
        #expect(Calculator.evaluate("2 + 2", currencies: currencies).first?.note == nil)
    }
}

@Suite struct SystemLoadTests {
    @Test func summarizes() {
        let load = SystemLoad(cpu: 0.123, gpu: 0.03, memoryUsed: 19_756_849_152, memoryTotal: 51_539_607_552,
                              download: 1_234_567, upload: 40_200)
        #expect(load.summary == "CPU 12% · GPU 3% · RAM 18.4/48 GB · ↓ 1.2 MB/s ↑ 40 KB/s")
    }

    @Test func showsUnknownPartsAsEllipsis() {
        #expect(SystemLoad().summary == "CPU … · GPU … · RAM … · ↓ … ↑ …")
        #expect(SystemLoad(gpu: 0, memoryUsed: 1 << 30, memoryTotal: 16 << 30).summary
            == "CPU … · GPU 0% · RAM 1/16 GB · ↓ … ↑ …")
    }

    @Test func formatsRates() {
        #expect(SystemLoad.rate(0) == "0 B/s")
        #expect(SystemLoad.rate(512) == "512 B/s")
        #expect(SystemLoad.rate(999.7) == "1.0 KB/s")
        #expect(SystemLoad.rate(9_940) == "9.9 KB/s")
        #expect(SystemLoad.rate(40_200) == "40 KB/s")
        #expect(SystemLoad.rate(3_500_000_000) == "3.5 GB/s")
        #expect(SystemLoad.percent(1.7) == "100%")
    }
}

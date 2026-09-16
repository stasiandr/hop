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

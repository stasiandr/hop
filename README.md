# hop

A minimal, fast, configurable launcher for macOS. Press a hotkey, type a few
letters, hit Return.

- Native Swift + AppKit, no dependencies
- No Dock icon, no menu bar icon, no Accessibility permission needed
- Everything lives in one TOML file

## Build & run

```sh
scripts/bundle.sh          # → build/hop.app
open build/hop.app
```

Press `⌥ Space` to open the panel. To start hop at login, add `build/hop.app`
(or a copy in `/Applications`) under System Settings → General → Login Items.

## Keys

| Key | Action |
| --- | --- |
| `↑` `↓` / `Tab` `⇧Tab` / `⌃P` `⌃N` | Move selection |
| `Return` | Launch selected |
| `⌘1`…`⌘9` | Launch nth result |
| `Esc` | Clear query, then close |

Type `edit config` or `quit hop` for built-in commands.

## Configuration

`~/.config/hop/config.toml` (or `$XDG_CONFIG_HOME/hop/config.toml`) is created
on first launch. Changes are picked up the next time the panel opens; if the
file has an error, hop keeps the last good config and shows the error in the
panel.

```toml
hotkey = "alt+space"   # modifiers: cmd, alt/opt, ctrl, shift
width = 640
max_results = 8

[[app]]
path = "/Applications/Safari.app"
alias = ["web", "browser"]

[[app]]
bundle = "com.microsoft.VSCode"   # resolved via LaunchServices
name = "Code"
alias = "vs"
```

Each `[[app]]` needs exactly one of `path` or `bundle`. `name` defaults to the
bundle's file name; `alias` is a string or a list of strings.

## Development

```sh
swift build
scripts/test.sh   # swift test, with a workaround for Command Line Tools
```

`Sources/HopCore` holds the platform-independent logic (TOML subset parser,
config model, hotkey parsing, fuzzy matcher) and is fully unit-tested.
`Sources/Hop` is the thin AppKit shell.

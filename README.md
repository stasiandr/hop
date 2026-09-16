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

Press `⌥ Space` to open the panel. Set `launch_at_login = true` in the config to
start hop with your session.

### Taking over ⌘ Space from Spotlight

Disable "Show Spotlight search" under System Settings → Keyboard → Keyboard
Shortcuts → Spotlight (or with [mac-and-conf](#with-mac-and-conf)), then set
`hotkey = "cmd+space"`.

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
launch_at_login = true # writes ~/Library/LaunchAgents/dev.hop.launcher.plist

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

The config file may be a symlink (e.g. into a dotfiles repo); edits to the
target are picked up too.

### With mac-and-conf

```toml
[tools.hop]
repo = "git@github.com:stasiandr/hop.git"
path = "~/personal/hop"
build = "scripts/bundle.sh"   # rebuilt by `apply` whenever the checkout changes
links = { "~/Applications/hop.app" = "build/hop.app" }

[dotfiles]
"~/.config/hop/config.toml" = "dotfiles/hop/config.toml"

[symbolic_hotkeys]
spotlight = false   # free ⌘ Space for hop
```

## Development

```sh
swift build
scripts/test.sh   # swift test, with a workaround for Command Line Tools
```

`Sources/HopCore` holds the platform-independent logic (TOML subset parser,
config model, hotkey parsing, fuzzy matcher) and is fully unit-tested.
`Sources/Hop` is the thin AppKit shell.

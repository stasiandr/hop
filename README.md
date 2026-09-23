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
| `↑` `↓` / `Tab` `⇧Tab` / `⌃P` `⌃N` | Move selection (Tab completes paths) |
| `Return` | Launch selected |
| `⌘Return` | Alternative action (projects: `project.alt_open`) |
| `⌘1`…`⌘9` | Launch nth result |
| `Esc` | Clear query, then close |

Type `edit config` or `quit hop` for built-in commands.

Activity Monitor is always in the list; its subtitle shows the current load,
updated every second while the panel is open:
`CPU 12% · GPU 3% · RAM 18.4/48 GB · ↓ 1.2 MB/s ↑ 40 KB/s`.

## Files and folders

Type a path starting with `~` or `/` to open it: `~/notes/index.json`. Results
complete the last component as you type (`~/personal/ho` → `~/personal/hop/`,
`~/personal/` lists the folder; hidden entries show once you type the dot).
Tab puts the selected path in the field, so `~/pe` Tab `ho` Tab gets you to
`~/personal/hop/`; Tab on a folder that's already typed steps into its first
entry.
Return opens the file or folder with `project.open` (say, your editor),
⌘Return opens a folder — or a file's folder — with `project.alt_open` (say, a
terminal). Without `[project]` settings they open in their default app.

## Calculator

Type a calculation and the answer shows up on top of the results. Return copies
the number, ⌘Return copies it with units.

| Query | Result |
| --- | --- |
| `2^10 + sqrt(16)` | `1028` |
| `200 + 15%`, `15% of 80` | `230`, `12` |
| `90 min to h` | `1.5 h` |
| `5400 s` | `1.5 h`, `1 h 30 min` |
| `1h 30min in min` | `90 min` |
| `1.5 GB in MiB` | `1430.511475 MiB` |
| `100 Mbit to MB` | `12.5 MB` |
| `1 GB / 10 MB/s` | `100 s` |
| `100 km / 2 h` | `50 km/h` |
| `100 F to C` | `37.77777778 °C` |
| `255 to hex`, `0xff` | `0xff`, `255` |
| `100 usd to rub`, `$20 + 15%` | `8123.45 RUB`, `23 USD` |
| `100 eur` | the same in `currencies` from the config |

Conversions use `to`, `in`, `as` or `->`. Units: length, mass, time, volume,
temperature, angles, speed, frequency and data. Data follows SI/IEC: `KB`,
`MB`, `GB` are powers of 1000, `KiB`, `MiB`, `GiB` powers of 1024; bits are
spelled out (`Mbit`, `Mbps`). Unit names ignore case. Functions: `sqrt`,
`cbrt`, `abs`, `round`, `floor`, `ceil`, `sin`/`cos`/`tan` (radians or `deg`),
`asin`/`acos`/`atan`, `ln`, `log` (base 10), `lg` (base 2), `exp`; constants
`pi`, `e`, `tau`; `mod` for remainder.

Currencies go by ISO code (`usd`, `rub`, `gel`), symbol (`$`, `€`, `₽`, `₾`) or
name (`dollars`, `euros`, `rubles`), plus `btc` and `eth`. An amount without a
target is shown in `currencies = ["USD", "EUR"]` from the config, which
defaults to your region's currency, USD and EUR. Rates come from
[exchange-api](https://github.com/fawazahmed0/exchange-api): hop fetches them
when the panel opens and the cached copy is over 12 hours old, and keeps them
in `~/Library/Caches/hop/usd.json` for offline use.

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

### Inventory: apps and projects from elsewhere

```toml
inventory = "~/.local/state/mac-and-conf/inventory.json"
exclude = ["unity-hub"]              # inventory names to skip

[project]
open = "dev.zed.Zed"                 # Return
alt_open = "com.mitchellh.ghostty"   # ⌘Return
```

The inventory is JSON with `apps` (`name`, `path` to a .app), `tools`
(`name`, `path` to a folder, shown as projects) and `unity` (`name`, `path`,
`version` of Unity projects). Return on a Unity project brings its editor to
the front if the project is already open, otherwise runs `unity open`; if that
fails (say, the editor version isn't installed) the project goes to
[uhub](https://github.com/stasiandr/uhub), which offers to install it. ⌘Return
uses `project.alt_open` like any other project. hop reloads it when it
changes. Projects that are git working trees show their current branch
(read when the panel opens). An `[[app]]` for the same bundle wins, so it can add aliases. Without
`[project]` settings projects open in Finder; with only one of them set, both
keys use it.

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

`mac-and-conf apply` writes the inventory with apps from your casks and
projects from `[tools]`; point `inventory` at it (see above).

## Development

```sh
swift build
scripts/test.sh   # swift test, with a workaround for Command Line Tools
```

`Sources/HopCore` holds the platform-independent logic (TOML subset parser,
config model, hotkey parsing, fuzzy matcher) and is fully unit-tested.
`Sources/Hop` is the thin AppKit shell.

# User-editable keybindings config with fallback

Created 2026-07-13 to replace hardcoded KidulWM shortcuts with a single config file that degrades safely.

## Path

User copy: `~/.config/kidulwm/keybinds.conf`

Repo default: `config/keybinds.conf`

System copy after `zig build`: `$prefix/share/kidulwm/keybinds.conf`

## Behaviour

- KidulWM loads `~/.config/kidulwm/keybinds.conf` at `Server.init` time.
- If the file is missing, malformed, has an empty binding list, or references an unknown key/action, it logs the problem and falls back to the compiled-in defaults.
- Hardcoded shortcuts in `src/input/keyboard.zig` are removed; all key handling comes from this table.

## Syntax

```
# comment
Mod4+<key> = <action>
```

Accepted prefixes: `Mod4+` or `Mod+`. Only `Mod4` modifier is supported by the current parser.

## Built-in default actions

- `focus_next`
- `focus_prev`
- `tray_toggle`
- `tray_select_next`
- `tray_select_prev`
- `tray_activate`
- `next_animation`
- `open_slide`              (spawns `/usr/bin/ghostty`)
- `spawn <command>`         (any command, e.g. `spawn /usr/bin/firefox`)

## Recommended default bindings

```
Mod4+Return     = open_slide
Mod4+j          = focus_next
Mod4+k          = focus_prev
Mod4+t          = tray_toggle
Mod4+Down       = tray_select_next
Mod4+Up         = tray_select_prev
Mod4+space      = tray_activate
Mod4+a          = next_animation
```

Avoid assigning two actions to the same key; the parser stops at the first match.

## Implementation notes

- `keybinds.zig` defines `Action` as a union with `spawn: []const u8` plus the intrinsic actions.
- Keys are mapped by name to `xkb.Keysym.*` constants. Numeric keys must be referenced as `xkb.Keysym.@"0"`, etc.
- The current parser is intentionally small. If you add more modifier support or chord parsing, keep the fallback path so a bad line still leaves the compositor usable.

## Zig 0.16 file-reading pitfall

This project runs on a CachyOS Zig 0.16 toolchain where `std.fs.openFileAbsolute` and `std.process.getEnvVarOwned` are not available. Use `std.c.getenv` to read `HOME`, build the path with `std.fs.path.join`, then read the file with raw `std.os.linux.open/read/close` syscalls. See the committed `src/config/keybinds.zig` for the working pattern.

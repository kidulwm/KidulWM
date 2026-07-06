# KidulWM Widget & Settings Protocol

This spec defines how GTK4 widgets (including the settings tray) communicate with the KidulWM Zig compositor. It is designed to be **developer-friendly**: a widget is just a process that can read JSON and render a surface.

## 1. Transport

- Primary: Unix domain socket at `$XDG_RUNTIME_DIR/kidulwm/ipc`.
- Fallback: `$KIDULWM_SOCKET` overrides the path.
- Message framing: newline-delimited JSON (NDJSON).
- Encoding: UTF-8.

## 2. Connection Handshake

A widget connects and immediately sends a `register` message. The compositor replies with `state_snapshot`.

```json
{"type": "register", "name": "kidul-brightness", "version": 1, "capabilities": ["subscribe", "emit"], "subscriptions": ["layout", "theme", " volume"], "surface": {"anchor": "right", "width": 80, "height": 320}}
```

- `name` — unique reverse-DNS widget ID.
- `capabilities` — `subscribe`, `emit`, `control`.
- `subscriptions` — topics the widget wants.
- `surface` — desired anchor, dimensions. The compositor may override geometry in `placement`.

## 3. Compositor → Widget Messages

### 3.1 `state_snapshot`
Dump of current state on connect.

```json
{"type": "state_snapshot", "output": "DP-1", "layout": {"split": [8, 94, 8], "gap": 8, "focused_column_rect": [100, 32, 1812, 1048]}, "theme": {"electric_blue": "#00f0ff", "royal_purple": "#a259ff", "turquoise": "#00ffc8", "background": "#0a0e17", "border": "#1a2b3c"}, "workspaces": [{"id": 1, "name": "dev"}]}
```

### 3.2 `state_update`
Delta update pushed whenever subscribed topic changes.

```json
{"type": "state_update", "topic": "theme", "value": {"electric_blue": "#ff00ff"}}
```

### 3.3 `placement`
Compositor tells the widget where to position its layer-shell surface.

```json
{"type": "placement", "rect": [1900, 32, 80, 320], "exclusive_zone": 0}
```

### 3.4 `toast`
Short-lived user-facing message; widgets may ignore.

```json
{"type": "toast", "text": "Volume 42%", "expires_ms": 2000}
```

## 4. Widget → Compositor Messages

### 4.1 `event`
A user interaction from the widget.

```json
{"type": "event", "target": "system", "action": "volume_up"}
```

Actions are mapped in KidulWM config. Examples: `volume_up`, `brightness_down`, `focus_next`, `workspace_switch`, `toggle_settings_tray`.

### 4.2 `config_patch`
**Only allowed for the settings tray and privileged widgets.** Writes a live configuration patch.

```json
{"type": "config_patch", "path": "layout.split", "value": [10, 92, 8]}
```

Paths follow the TOML/JSON config schema. The compositor validates, applies, and broadcasts the update.

### 4.3 `command`
One-off compositor command without persistent config change.

```json
{"type": "command", "action": "reload_config"}
```

## 5. Settings Tray Protocol

The settings tray is a **privileged widget** named `kidul-settings`. It uses `config_patch` for live adjustments.

Supported config patches:

| Path | Type | UI Control |
|------|------|------------|
| `layout.split` | `[int, int, int]` | Three percentage sliders |
| `layout.gap` | int px | Spinner |
| `layout.min_peek_px` | int px | Spinner |
| `decoration.corner_style` | `"cut"\|"classic"\|"none"` | Radio |
| `decoration.corner_depth` | int px | Spinner |
| `decoration.border_width` | int px | Spinner |
| `theme.*` | hex colour | Colour picker |
| `input.edge_width` | int px | Spinner |

### 5.1 Preview Semantics
- `config_patch` is applied immediately on the compositor side.
- The compositor broadcasts `state_update` to all subscribers.
- The tray UI updates itself from the same broadcast, keeping it synced.

### 5.2 Presets
- `config_patch` to `layout.profile` or `theme.profile` selects a named preset.
- User can save current state as a new preset.

## 6. Widget Manifest

Every widget should ship a `manifest.json`:

```json
{
  "id": "com.example.kidul.clock",
  "name": "Kidul Clock",
  "version": "1.0.0",
  "entry": "./kidul-clock",
  "surface": {"anchor": "right", "width": 80, "height": 80},
  "subscriptions": ["tick", "theme"],
  "events": ["none"]
}
```

The compositor discovers widgets by scanning `$XDG_CONFIG_HOME/kidulwm/widgets/*/manifest.json`.

## 7. Developer SDK

`examples/widgets/` provides:
- `clock/` — minimal Zig widget.
- `volume/` — widget that emits events.
- `settings/` — privileged tray demonstrating `config_patch`.
- `python-clock/` — same widget in Python for quick iteration.

## 8. Security Notes

- Only widgets whose executable path is owned by root or the user and listed in `trusted_widgets` can send `config_patch`.
- Untrusted widgets may only subscribe and emit generic actions.
- Widgets run as separate Wayland clients; a crashed widget does not take down the compositor.

## 9. Future Directions

- Wayland sub-protocol (`kidul_widget_manager_v1`) to replace Unix socket.
- Widget sandboxing with `xdg-portal`-style capabilities.
- Remote widgets streamed over the secure remote-desktop control channel.

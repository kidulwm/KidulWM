# Cinematic Black-Gold Weather Peek + Surf Card

> **For Hermes:** Use subagent-driven-development discipline. Implement task-by-task, build after each task, and ping the user only when a task is verified.

**Goal:** Add a KidulWM compositor-internal weather/surf widget in the left peek, and a matching TrayCard detail view (calendar-card size) opened by clicking it. Moon phase, surf/weather data, satellite timeline, all in black-gold cinematic theming.

**Architecture:** Same Cairo→wlroots scene-buffer overlay pipeline as the clock/calendar TrayCard. A tiny out-of-process data helper fetches Open-Meteo (primary), NOAA/NWS fallback, and token-based providers, writing JSON caches KidulWM consumes. Moon phase is computed locally. Satellite tiles are fetched hourly, themed, and scrubbed via a timeline slider.

**Tech Stack:** Zig (compositor widget), Cairo, Python 3 + curl + tzdata (data helper), Open-Meteo API, NOAA/NWS, optional Stormglass/tokens.

**Defaults accepted from user:** idle-break threshold = 10 min, key-press animation then every 15 min active; surf left, weather right in card; one location per card; calendar link follow-up; start with moon outline, add Ratu Kidul crescent still later as toggleable asset.

---

## Task 1: Scaffold weather module and theme tokens

**Objective:** Create the new source files and theme tokens so later tasks have a place to live.

**Files:**
- Create: `src/ui/weather.zig` (empty module shell, `WeatherWidget` struct with required lifecycle).
- Create: `src/util/moon.zig` (Julian date, phase angle, illumination fraction helpers).
- Modify: `src/core/style.zig` — add `weather_moon_color`, `weather_temp_color`, `weather_minmax_color`, `weather_icon_color`, `weather_anim_color`, `weather_widget_min_width`, `weather_peek_anim_budget_ms`.
- Modify: `src/core/theme.zig` — parse new tokens from `theme.toml`.
- Modify: `config/theme.toml` — add values in black-gold palette.
- Modify: `build.zig` — add `src/ui/weather.zig` module.

**Steps:**
1. Add semantic tokens to `config/theme.toml` (use focused border color for moon outline initially).
2. Add matching fields to `Style` with sensible defaults.
3. Parse tokens in theme loader; default to existing tokens when missing.
4. Create empty `src/ui/weather.zig` with `const WeatherWidget = @This(); pub fn init(...) void {} pub fn deinit() void {}`.
5. Create `src/util/moon.zig` with `phaseForUnixSeconds(utc_s: i64) struct { illum: f64, age: f64, name: []const u8 }`.
6. Reference `src/ui/weather.zig` from `build.zig` as a module export.

**Verification:**
- `zig build` succeeds.
- `grep weather_ config/theme.toml src/core/style.zig src/core/theme.zig` returns matches.
- Commit.

---

## Task 2: Moon phase renderer (still, outline, local)

**Objective:** Draw the current moon phase as a dark circle with an illuminated arc, in the focused border color, inside a left-peek area.

**Files:**
- Modify: `src/ui/weather.zig`
- Modify: `src/util/moon.zig`

**Steps:**
1. Compute phase from local clock every minute (no need every frame).
2. Add `renderMoon(cr, cx, cy, r, phase, color)`:
   - Draw full disk outline in border color.
   - Fill dark side with near-black (color_background at ~0.9 alpha).
   - Fill lit side using a clipped ellipse arc determined by phase age.
3. Export a function `renderMoonForBox(cr, box, phase, style)` that centers the moon and respects top padding.

**Verification:**
- Add a temporary `tray.weather_moon_test` IPC or unit test path that renders to `/tmp/moon_test.png`.
- `zig build` succeeds.
- Inspect `/tmp/moon_test.png` shows new/crescent/quarter/gibbous/full shapes across simulated dates.
- Commit.

---

## Task 3: Weather data helper skeleton

**Objective:** Stand up a tiny Python helper that fetches Open-Meteo and caches a normalized JSON the compositor can read synchronously.

**Files:**
- Create: `tools/fetch_weather.py`
- Create: `tools/weather_providers.py` (OpenMeteoProvider, NOAAProvider, TokenProvider interface)
- Create: `tools/cache.py` (read/write `~/.cache/kidulwm/weather/<location_slug>.json`)
- Create: `tools/normalize.py` (common schema: current, hourly[], daily[], marine/swell/tides)

**Steps:**
1. Implement OpenMeteoProvider:
   - Air: `https://api.open-meteo.com/v1/forecast?latitude=...&longitude=...&current=temperature_2m,weather_code&hourly=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset&timezone=auto`
   - Marine: `https://marine-api.open-meteo.com/v1/marine?latitude=...&longitude=...&hourly=wave_height,swell_wave_height,swell_wave_direction,swell_wave_period&daily=wave_height_max`
2. Implement NOAAProvider as stub for US waters (NDBC buoy summary or NWS marine forecast).
3. Normalize to shared schema with these fields:
   - `current.temp`, `current.weather_code`, `current.wind_speed`, `current.wind_dir`
   - `daily[]`: date, temp_min, temp_max, sunrise, sunset
   - `hourly[]`: timestamp, air_temp, weather_code, wind_speed, wind_dir, wave_height, swell_height, swell_dir, swell_period
   - `tides[]`: timestamp, height (from Open-Meteo tides where available, else empty)
4. Cache to `~/.cache/kidulwm/weather/<slug>.json` with `updated_at` timestamp.
5. CLI: `fetch_weather.py --lat ... --lon ... --slug home --providers openmeteo,noaa`.

**Verification:**
- `python3 tools/fetch_weather.py --lat -33.8688 --lon 151.2093 --slug sydney` writes valid JSON.
- JSON passes a small jq schema check (`jq '.current, .hourly[0], .daily[0]'`).
- Commit.

---

## Task 4: Compositor polling and cache reader

**Objective:** `WeatherWidget` reads the cache, updates on a configurable interval, and triggers redraw.

**Files:**
- Modify: `src/ui/weather.zig`

**Steps:**
1. Add `WeatherState` fields: current, daily[], hourly[].
2. Add a timer (`std.time.milliTimestamp`) that triggers a read from `~/.cache/kidulwm/weather/home.json` every 10 minutes.
3. Parse JSON with `std.json` (or via `std.json.Parser`) into small structs. Keep only fields we display.
4. Set `needs_redraw = true` after parse.
5. If file missing, show a "set location" prompt mini-card in the peek.

**Verification:**
- Put the sample Sydney cache from Task 3 in place.
- Temporarily log parsed current temp; confirm via `journalctl`.
- `zig build` succeeds.
- Commit.

---

## Task 5: Peek weather text layout

**Objective:** Render current temp (large), min/max (small), and center them as peek width changes.

**Files:**
- Modify: `src/ui/weather.zig`

**Steps:**
1. Define `layoutForPeek(w, h, style)` returning:
   - moon center/radius at top
   - current temp baseline
   - min/max baseline
   - icon/animation box at bottom
2. Current temp font size = `tray_font_size * 2.2`.
3. Min/max font size = `tray_font_size * 0.85`, placed below current temp.
4. If peek width > `weather_widget_min_width`, center the group; else left-align at 4 px from screen edge.
5. Render onto a Cairo surface sized to the left-peek box.

**Verification:**
- Build, deploy to a test VM, open tray, screenshot.
- Confirm text is readable and centered in normal width, hugs edge at minimum width.
- Commit.

---

## Task 6: Weather icon + animation state machine

**Objective:** Draw a simple icon for current condition and add a subtle animation triggered by typing idle break.

**Files:**
- Modify: `src/ui/weather.zig`
- Modify: `src/input/keyboard.zig` — hook key event to call `weather.onKeyActivity()`

**Steps:**
1. Map Open-Meteo WMO weather codes to an enum: Clear, Cloudy, Rain, HeavyRain, Snow, Thunder, Fog, Frost.
2. Draw icons procedurally in Cairo:
   - Clear: small star/sun glyph.
   - Cloudy: soft cloud outline.
   - Rain: 2-3 droplet outlines.
   - Snow: small snowflake outline.
   - Thunder: simple lightning bolt.
   - Frost: crystal outline.
3. Animation state machine:
   - Tracks `last_key_ms`, `last_anim_ms`, `idle_break_ms = 10 min`, `active_interval_ms = 15 min`.
   - On `onKeyActivity()`: if `now - last_key_ms > idle_break_ms`, set `animation_active_until = now + 3s`.
   - During active window, replay animation every 15 minutes.
   - Heavy rain triggers one quick "pour" burst (20-30 particles) then pause for active interval.
   - Light rain/snow: 3-8 particles drifting down over 4-8 s.
   - Clear: single tiny twinkle on star icon.
   - Cloudy: subtle cloud outline opacity pulse.
4. Keep particle count ≤ 40; store in a small fixed array on `WeatherWidget`.

**Verification:**
- Build and deploy.
- Trigger animation via `kidulwm-control sim_weather_anim` (add IPC command first), screenshot.
- Confirm animation stops after burst/pulse and does not loop continuously.
- Commit.

---

## Task 7: Hook into tray / left peek

**Objective:** Place the widget in the left peek beside the Bob logo, below the MAIN/Hide area, matching tray layout rules.

**Files:**
- Modify: `src/ui/tray.zig`
- Modify: `src/ui/weather.zig`

**Steps:**
1. Add `Tray.weather: WeatherWidget`.
2. In `Tray.update()` after the panel is drawn, call `self.weather.update(self.left_peek_box, self.host.theme)`.
3. Pass keyboard activity from `keyboard.zig` to `tray.weather.onKeyActivity()`.
4. Click inside the left peek weather bounds opens the weather TrayCard.
5. In fullscreen, disable/raise-behind the widget scene tree.

**Verification:**
- Build, deploy, open tray.
- Moon + temps render in left peek.
- Click opens weather card placeholder.
- Commit.

---

## Task 8: Weather TrayCard layout (surf left, weather right, timeline slider)

**Objective:** Build the detail card, same size/positioning as calendar card, using calendar-card glass styling.

**Files:**
- Modify: `src/ui/weather.zig`
- Modify: `src/ui/tray.zig` (card open/close hook)

**Steps:**
1. Add `WeatherCard` struct with `open`, `selected_date`, `selected_hour`, `timeline_offset`.
2. Card size = calendar card bounds; initial position logic reused from `TrayCard`.
3. Top bar: surf summary left (wave height, swell direction/period, wind), weather summary right (temp, condition, wind).
4. Below summary: timeline slider (same visual style as future calendar timeline): one horizontal pill with scrub handle, spans available history+forecast.
5. Click/scrub slider updates `selected_hour` and re-renders satellite/map snapshot and hourly details.
6. Bottom section: hourly strip (temp, weather icon, waves) and daily min/max list.

**Verification:**
- Build, deploy, click weather widget.
- Card appears sized like calendar.
- Slider scrubs visible.
- Commit.

---

## Task 9: Satellite tile fetch + themed render

**Objective:** Download regional satellite tiles once per hour, recolor to black-gold, and draw into the timeline.

**Files:**
- Create: `tools/fetch_satellite.py`
- Modify: `src/ui/weather.zig`

**Steps:**
1. `fetch_satellite.py` fetches NASA GIBS / EOSDIS PNG tiles for a configurable bbox (from settings) every hour.
2. Save to `~/.cache/kidulwm/satellite/<timestamp>_<zoom>_<x>_<y>.png`.
3. Prune to last 24 hours by default.
4. In `weather.zig`, read nearest cached timestamp for selected slider position.
5. Load PNG with Cairo, map to card region, and recolor with a black-gold LUT (desaturate, shift yellow/gold highlights, crush shadows).
6. If tiles missing or offline, draw a styled "satellite unavailable" placeholder.

**Verification:**
- Run `tools/fetch_satellite.py --lat ... --lon ...` manually; inspect PNG.
- Build/deploy; slider should show themed satellite frame.
- Commit.

---

## Task 10: Provider config UI / settings integration stub

**Objective:** Let users change location and providers via config until the settings card exists.

**Files:**
- Create: `config/weather.toml` example
- Create: `tools/weather_config.py` (read `~/.config/kidulwm/weather.toml`)

**Steps:**
1. File format:
   ```toml
   [location]
   name = "Sydney"
   lat = -33.87
   lon = 151.21

   [providers]
   primary = "openmeteo"
   marine = "openmeteo_marine"
   satellite = "gibs"

   [tokens]
   # optional provider tokens here
   ```
2. The data helper reads this file instead of CLI args when run from KidulWM.
3. Add a simple `kidulwm-control weather_set_location "Name" lat lon` IPC stub that rewrites the file and triggers a fetch.

**Verification:**
- Write sample config, run helper, confirms fetch.
- IPC rewrites file correctly.
- Commit.

---

## Task 11: Favorites list

**Objective:** Store up to 5 favorite locations and cycle/switch in the card.

**Files:**
- Modify: `config/weather.toml`
- Modify: `tools/weather_config.py`
- Modify: `src/ui/weather.zig`

**Steps:**
1. Add `[[favorites]]` entries to TOML.
2. In WeatherCard, render favorite chips (gold outline pill buttons) across the top under surf/weather summary.
3. Clicking a favorite swaps active location, re-reads cache, redraws.
4. `kidulwm-control weather_add_favorite` / `weather_cycle_favorite` IPC.

**Verification:**
- Add two favorites, confirm card switches.
- Commit.

---

## Task 12: Calendar link (follow-up, optional)

**Objective:** Calendar can display small moon phase glyph + weather icon for days within forecast range.

**Files:**
- Modify: `src/ui/tray.zig` calendar draw helper.

**Steps:**
1. Add function `calendarDayOverlay(cr, year, month, day) -> ?Icon` that asks WeatherWidget for moon phase and forecast snapshot.
2. For future days up to forecast limit, draw tiny condition icon in cell corner.
3. For past days, draw actuals from stored home cache if available.
4. For all days, draw a tiny moon phase crescent near the day number.

**Verification:**
- Screenshot calendar; confirm moon glyphs on cells.
- Commit.

---

## Task 13: Final integration, cleanup, documentation

**Objective:** Remove debug logging, update HANDOFF.md, KNOWN_CMDS.md, add default IPC commands.

**Files:**
- Modify: `src/ipc/message.zig`
- Modify: `src/kidulwm-control.zig`
- Modify: `HANDOFF.md`
- Modify: `KNOWN_CMDS.md`
- Modify: `config/theme.toml` (remove any temporary diagnostic colors)

**Steps:**
1. Add IPC commands: `weather_toggle_card`, `weather_set_location`, `weather_cycle_favorite`, `weather_sim_anim`, `weather_reload`.
2. Document commands in KNOWN_CMDS.md.
3. Update HANDOFF.md fallback commit and last stable commit.
4. `zig build` clean.

**Verification:**
- Full build and deploy on a disposable VM.
- Smoke test every IPC command.
- Commit and tag fallback.

---

## Risks & Tradeoffs

- Open-Meteo rate limits/free tier: we poll every 10 min but respect `Cache-Control` and back off on HTTP 429.
- Satellite tiles: NASA GIBS requires attribution and is not live radar; it gives cloud imagery, not color IR. Deemed acceptable for "themed satellite" layer.
- Compositor memory: satellite images cached to disk, compositor loads only the frame currently selected; keep max one Cairo surface in RAM.
- Animation budget: fixed 40 particles max; no continuous loops to protect battery.
- Network code deliberately outside compositor so crashes/timeouts never hang rendering.

## Open questions for coderBob before Task 1

None — defaults are locked. If a task hits an API or library issue, stop, report, and propose a narrower fallback.

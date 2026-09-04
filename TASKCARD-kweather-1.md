# TASKCARD kweather-1 — weather satellite slide

Goal: weather peek-widget click spawns a full kweather slide (satellite app),
replacing the in-compositor weather card. Pattern = ksignals beacon click.

## Reading list (read FIRST, in order)
1. /home/dad/dev/kslide-template/src/App.zig — satellite app interface + GLOBAL INPUT LAW
2. /home/dad/dev/kslide-template/src/Wayland.zig, Theme.zig, build.zig
3. /home/dad/dev/KidulWM/src/ui/tray.zig:962-985 — toggleSignalsCard spawn pattern (pkill + spawn)
4. /home/dad/dev/KidulWM/src/ui/weather.zig:520-580 — cache JSON parse + cachePath()
5. /home/dad/dev/KidulWM/config/theme.toml — weather_moon/temp/minmax/icon colors

## Data source
~/.cache/kidulwm/weather/home.json — fields: location_name, current{temp,
weather_code,is_day,wind_speed,wind_dir}, daily[{temp_min,temp_max}],
hourly[{wave_height,swell_height,swell_dir,swell_period}].
Location now Toowoomba QLD (-27.56, 151.95), refreshed every 15 min by
kidulwm-weather.timer on the host.

## Stage 1 (this dispatch): scaffold + host smoke
- cp -r /home/dad/dev/kslide-template /home/dad/dev/kweather; git init;
  B&B signed initial commit ('B&B' <bnb@ratukidultech.com>,
  GPG 344B8C86C2E835F1AF9766E40AE9A7E153BFA843).
- Binary name kweather. App.zig: load home.json, render slide:
  location pill top, big temp center, weather-code condition text/icon
  (reuse the wmo code→label mapping style from KidulWM weather.zig),
  min/max, wind. House look: card_mat bg, textbox panel, gold text.
- Input law: Up/Down/Left/Right/Enter/Esc per template; Esc closes.
  HARD STOPS, no cycling.
- zig build green; WAYLAND_DISPLAY=wayland-1 smoke-run on host (host runs
  KidulWM session; Niri also on wayland-1 in dev shells — check
  KIDULWM_WAYLAND_DISPLAY env / use the running compositor socket).
- Signed commit per stage.

## Stage 2 (next dispatch, needs your green light): wire the click
- tray.zig handlePointerClick weather arm → closeAllCards + spawn kweather
  (pkill kweather first, same as toggleSignalsCard); delete the
  weather-card render/toggle paths only after slide verified live.

## NOT this session
- No calendar/files/network slide work. No upstream issues/PRs.
- No changes to fetch-weather.py or the timer (already live).
- No moon renderer in v1 (widget keeps the moon; slide may add later).

## Verification bar
- Cold-cache build: rm -rf .zig-cache zig-out && zig build.
- Self-report is not proof — parent re-verifies build + run.
- Flag deviations, never silently accept them.

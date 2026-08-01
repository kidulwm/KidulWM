#!/usr/bin/env python3
"""Fetch real weather/marine data from Open-Meteo and write KidulWM cache."""

import configparser
import json
import os
import pathlib
import urllib.request
import urllib.error


def load_config() -> dict:
    config = configparser.ConfigParser()
    config.read(os.path.expanduser("~/.config/kidulwm/weather.conf"))
    if not config.has_section("weather"):
        return {
            "location_name": "Svalbard",
            "lat": 78.2232,
            "lon": 15.6267,
        }
    section = config["weather"]
    return {
        "location_name": section.get("location_name", "Svalbard"),
        "lat": section.getfloat("lat", 78.2232),
        "lon": section.getfloat("lon", 15.6267),
    }


def fetch_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "KidulWM/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> int:
    cfg = load_config()
    lat = cfg["lat"]
    lon = cfg["lon"]

    weather_url = (
        f"https://api.open-meteo.com/v1/forecast?"
        f"latitude={lat}&longitude={lon}&timezone=auto&"
        f"current=temperature_2m,weather_code,is_day,wind_speed_10m,wind_direction_10m&"
        f"daily=temperature_2m_max,temperature_2m_min"
    )

    marine_url = (
        f"https://marine-api.open-meteo.com/v1/marine?"
        f"latitude={lat}&longitude={lon}&"
        f"hourly=wave_height,swell_wave_height,swell_wave_direction,swell_wave_period"
    )

    try:
        weather = fetch_json(weather_url)
    except urllib.error.URLError as e:
        print(f"weather fetch failed: {e}")
        return 1

    try:
        marine = fetch_json(marine_url)
    except urllib.error.URLError:
        marine = None

    current = weather.get("current", {})
    daily = weather.get("daily", {})

    hourly_out = []
    if marine:
        m = marine
        hourly = m.get("hourly", {})
        for i in range(len(hourly.get("wave_height", []))):
            hourly_out.append({
                "wave_height": hourly.get("wave_height", [0.0])[i],
                "swell_height": hourly.get("swell_wave_height", [0.0])[i],
                "swell_dir": hourly.get("swell_wave_direction", [0])[i],
                "swell_period": hourly.get("swell_wave_period", [0.0])[i],
            })

    result = {
        "location_name": cfg["location_name"],
        "current": {
            "temp": current.get("temperature_2m", 0.0),
            "weather_code": current.get("weather_code", 0),
            "is_day": current.get("is_day", 1),
            "wind_speed": current.get("wind_speed_10m", 0.0),
            "wind_dir": current.get("wind_direction_10m", 0),
        },
        "daily": [
            {
                "temp_min": daily.get("temperature_2m_min", [0.0])[0] if daily.get("temperature_2m_min") else 0.0,
                "temp_max": daily.get("temperature_2m_max", [0.0])[0] if daily.get("temperature_2m_max") else 0.0,
            }
        ],
        "hourly": hourly_out,
    }

    cache_dir = pathlib.Path.home() / ".cache" / "kidulwm" / "weather"
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_path = cache_dir / "home.json"
    cache_path.write_text(json.dumps(result, indent=2))
    print(f"wrote {cache_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

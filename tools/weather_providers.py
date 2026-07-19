"""Provider implementations for the KidulWM weather helper."""
from __future__ import annotations

import json
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from abc import ABC, abstractmethod
from typing import Any

from normalize import Current, Daily, Hourly, Tide, WeatherBundle


class Provider(ABC):
    """Common interface for air/marine/tide providers."""

    @property
    @abstractmethod
    def name(self) -> str:
        """Short provider identifier."""

    @abstractmethod
    def fetch(self, lat: float, lon: float) -> WeatherBundle | None:
        """Return a normalized bundle or None if the provider is unavailable."""

    def _get_json(self, url: str, timeout: int = 20) -> dict[str, Any] | None:
        """Fetch JSON from a URL, returning None on failure."""
        try:
            with urllib.request.urlopen(url, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except (urllib.error.URLError, OSError, json.JSONDecodeError) as exc:
            # Log to stderr so journalctl can see provider failures.
            import sys

            print(f"{self.name}: fetch failed: {exc}", file=sys.stderr)
            return None


class OpenMeteoProvider(Provider):
    """Open-Meteo forecast API (air)."""

    @property
    def name(self) -> str:
        return "openmeteo"

    def fetch(self, lat: float, lon: float) -> WeatherBundle | None:
        params = urllib.parse.urlencode(
            {
                "latitude": lat,
                "longitude": lon,
                "current": "temperature_2m,weather_code,wind_speed_10m,wind_direction_10m",
                "hourly": "temperature_2m,weather_code,wind_speed_10m,wind_direction_10m",
                "daily": "temperature_2m_min,temperature_2m_max,sunrise,sunset",
                "timezone": "auto",
            }
        )
        url = f"https://api.open-meteo.com/v1/forecast?{params}"
        data = self._get_json(url)
        if data is None:
            return None

        current = data.get("current", {})
        hourly = data.get("hourly", {})
        daily = data.get("daily", {})

        bundle = WeatherBundle(
            latitude=lat,
            longitude=lon,
            provider=self.name,
            current=Current(
                temp=float(current.get("temperature_2m", 0.0)),
                weather_code=int(current.get("weather_code", 0)),
                wind_speed=float(current.get("wind_speed_10m", 0.0)),
                wind_dir=int(current.get("wind_direction_10m", 0)),
            ),
        )

        ts = hourly.get("time", [])
        temps = hourly.get("temperature_2m", [])
        codes = hourly.get("weather_code", [])
        winds = hourly.get("wind_speed_10m", [])
        dirs = hourly.get("wind_direction_10m", [])
        for i in range(min(len(ts), 24)):
            bundle.hourly.append(
                Hourly(
                    timestamp=str(ts[i]),
                    air_temp=float(temps[i]) if i < len(temps) else 0.0,
                    weather_code=int(codes[i]) if i < len(codes) else 0,
                    wind_speed=float(winds[i]) if i < len(winds) else 0.0,
                    wind_dir=int(dirs[i]) if i < len(dirs) else 0,
                )
            )

        dates = daily.get("time", [])
        mins = daily.get("temperature_2m_min", [])
        maxs = daily.get("temperature_2m_max", [])
        rises = daily.get("sunrise", [])
        sets = daily.get("sunset", [])
        for i in range(len(dates)):
            bundle.daily.append(
                Daily(
                    date=str(dates[i]),
                    temp_min=float(mins[i]) if i < len(mins) else 0.0,
                    temp_max=float(maxs[i]) if i < len(maxs) else 0.0,
                    sunrise=str(rises[i]) if i < len(rises) else "",
                    sunset=str(sets[i]) if i < len(sets) else "",
                )
            )

        return bundle


class OpenMeteoMarineProvider(Provider):
    """Open-Meteo marine API; fills wave/swell fields on an existing bundle."""

    @property
    def name(self) -> str:
        return "openmeteo_marine"

    def fetch(self, lat: float, lon: float) -> WeatherBundle | None:
        params = urllib.parse.urlencode(
            {
                "latitude": lat,
                "longitude": lon,
                "hourly": "wave_height,swell_wave_height,swell_wave_direction,swell_wave_period",
                "daily": "wave_height_max",
                "timezone": "auto",
            }
        )
        url = f"https://marine-api.open-meteo.com/v1/marine?{params}"
        data = self._get_json(url)
        if data is None:
            return None

        hourly = data.get("hourly", {})
        ts = hourly.get("time", [])
        waves = hourly.get("wave_height", [])
        swells = hourly.get("swell_wave_height", [])
        swell_dirs = hourly.get("swell_wave_direction", [])
        swell_periods = hourly.get("swell_wave_period", [])

        bundle = WeatherBundle(latitude=lat, longitude=lon, provider=self.name)
        for i in range(min(len(ts), 24)):
            bundle.hourly.append(
                Hourly(
                    timestamp=str(ts[i]),
                    wave_height=float(waves[i]) if i < len(waves) else None,
                    swell_height=float(swells[i]) if i < len(swells) else None,
                    swell_dir=int(swell_dirs[i]) if i < len(swell_dirs) else None,
                    swell_period=float(swell_periods[i]) if i < len(swell_periods) else None,
                )
            )
        return bundle


class NOAAProvider(Provider):
    """Stub for US NOAA/NWS marine products; returns empty bundle if no buoy near point."""

    @property
    def name(self) -> str:
        return "noaa"

    def fetch(self, lat: float, lon: float) -> WeatherBundle | None:
        # NOAA integration kept as a stub.  To be implemented with NDBC JSON or NWS API.
        import sys

        print(f"{self.name}: stub provider used for lat={lat} lon={lon}", file=sys.stderr)
        return WeatherBundle(latitude=lat, longitude=lon, provider=self.name)


def merge_marine(base: WeatherBundle, marine: WeatherBundle | None) -> None:
    """Copy wave/swell fields from the marine bundle into the air bundle by timestamp."""
    if marine is None:
        return
    for i, h in enumerate(base.hourly):
        for mh in marine.hourly:
            if mh.timestamp == h.timestamp:
                h.wave_height = mh.wave_height
                h.swell_height = mh.swell_height
                h.swell_dir = mh.swell_dir
                h.swell_period = mh.swell_period
                break


def get_providers(names: list[str]) -> list[Provider]:
    """Map provider identifier strings to Provider instances."""
    registry: dict[str, Provider] = {
        "openmeteo": OpenMeteoProvider(),
        "openmeteo_marine": OpenMeteoMarineProvider(),
        "noaa": NOAAProvider(),
    }
    return [registry[n] for n in names if n in registry]

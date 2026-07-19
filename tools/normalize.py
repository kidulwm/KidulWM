"""Shared normalized weather schema consumed by the KidulWM compositor."""
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass
class Current:
    """Most recent weather observation."""

    temp: float = 0.0
    weather_code: int = 0
    wind_speed: float = 0.0
    wind_dir: int = 0
    is_day: int = 0


@dataclass
class Daily:
    """One daily forecast entry."""

    date: str = ""
    temp_min: float = 0.0
    temp_max: float = 0.0
    sunrise: str = ""
    sunset: str = ""


@dataclass
class Hourly:
    """One hourly forecast entry."""

    timestamp: str = ""
    air_temp: float = 0.0
    weather_code: int = 0
    wind_speed: float = 0.0
    wind_dir: int = 0
    wave_height: float | None = None
    swell_height: float | None = None
    swell_dir: int | None = None
    swell_period: float | None = None


@dataclass
class Tide:
    """Optional tidal height entry."""

    timestamp: str = ""
    height: float = 0.0


@dataclass
class WeatherBundle:
    """Canonical shape written to ~/.cache/kidulwm/weather/<slug>.json."""

    location_name: str = ""
    latitude: float = 0.0
    longitude: float = 0.0
    updated_at: str = ""
    provider: str = ""
    current: Current = field(default_factory=Current)
    daily: list[Daily] = field(default_factory=list)
    hourly: list[Hourly] = field(default_factory=list)
    tides: list[Tide] = field(default_factory=list)

    def to_json(self) -> dict[str, Any]:
        """Flat dict representation; Zig side can read without nested dataclass parser."""
        flat = asdict(self)
        # Keep arrays of simple structs; compositor only reads first daily/hourly anyway.
        return flat

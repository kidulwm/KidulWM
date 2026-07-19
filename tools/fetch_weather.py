#!/usr/bin/env python3
"""KidulWM weather data helper.

Fetches Open-Meteo (and optional marine/noaa) data and writes a normalized
JSON cache to ~/.cache/kidulwm/weather/<slug>.json.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Keep helper self-contained; repository callers import from the same directory.
sys.path.insert(0, str(Path(__file__).parent))

from cache import CacheDir, now_rfc3339, stamp_epoch_ms
from normalize import WeatherBundle
from weather_providers import get_providers, merge_marine


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch weather and cache JSON for KidulWM.")
    parser.add_argument("--lat", type=float, required=True, help="Latitude")
    parser.add_argument("--lon", type=float, required=True, help="Longitude")
    parser.add_argument("--slug", type=str, default="home", help="Cache slug name")
    parser.add_argument("--providers", type=str, default="openmeteo", help="Comma-separated provider names")
    parser.add_argument("--name", type=str, default="", help="Human location name")
    args = parser.parse_args()

    provider_names = [p.strip() for p in args.providers.split(",") if p.strip()]
    providers = get_providers(provider_names)
    if not providers:
        print("No valid providers selected.", file=sys.stderr)
        return 1

    bundle: WeatherBundle | None = None
    for provider in providers:
        result = provider.fetch(args.lat, args.lon)
        if result is None:
            continue
        if provider.name == "openmeteo_marine":
            merge_marine(bundle, result) if bundle else None
        elif bundle is None:
            bundle = result

    if bundle is None:
        print("All providers failed.", file=sys.stderr)
        return 1

    bundle.location_name = args.name or bundle.location_name or args.slug
    bundle.updated_at = now_rfc3339()
    bundle.latitude = args.lat
    bundle.longitude = args.lon

    cache = CacheDir("weather")
    path = cache.write(args.slug, bundle.to_json())
    print(f"Wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

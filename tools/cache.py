"""Simple JSON read/write layer for KidulWM weather/satellite caches."""
from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any


class CacheDir:
    """Base cache bucket under ~/.cache/kidulwm."""

    def __init__(self, subdir: str) -> None:
        home = os.environ.get("HOME", os.path.expanduser("~"))
        self.base = Path(home) / ".cache" / "kidulwm" / subdir
        self.base.mkdir(parents=True, exist_ok=True)

    def path(self, slug: str) -> Path:
        """Filesystem path for a named cache entry."""
        slug = "".join(c for c in slug if c.isalnum() or c in ("-", "_", "."))
        return self.base / f"{slug}.json"

    def read(self, slug: str) -> dict[str, Any] | None:
        """Read a cached JSON file. Returns None if missing/unreadable."""
        p = self.path(slug)
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None

    def write(self, slug: str, data: dict[str, Any]) -> Path:
        """Atomically write JSON data and return the path written."""
        p = self.path(slug)
        tmp = p.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
        tmp.replace(p)
        return p

    def list_json(self) -> list[Path]:
        """Return every .json file in the bucket."""
        return sorted(self.base.glob("*.json"))


def now_rfc3339() -> str:
    """ISO-8601/RFC 3339 timestamp in UTC."""
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def stamp_epoch_ms() -> int:
    """Current wall-clock time in milliseconds since epoch."""
    return int(time.time() * 1000)

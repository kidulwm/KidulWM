#!/usr/bin/env python3
"""KidulWM system notification watcher.

Polls the same state files used by rkt-dashboard and forwards interesting
security and USB events into KidulWM as notifications.

State files read:
    ~/.local/share/rkt-dashboard/security/security-state.json
    ~/.local/share/rkt-dashboard/usb-pending.jsonl
    ~/.local/share/rkt-dashboard/usb-guard-state.json

Rules config:
    ~/.config/kidulwm/notifications.yaml
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
STATE_ROOT = Path(os.environ.get("RKT_DASHBOARD_STATE_DIR", HOME / ".local" / "share" / "rkt-dashboard"))
SECURITY_DIR = STATE_ROOT / "security"
SECURITY_STATE = SECURITY_DIR / "security-state.json"
USB_PENDING = STATE_ROOT / "usb-pending.jsonl"
USB_STATE = STATE_ROOT / "usb-guard-state.json"

CONFIG_DIR = HOME / ".config" / "kidulwm"
CONFIG_FILE = CONFIG_DIR / "notifications.yaml"

CHECK_INTERVAL = 5  # seconds


class Watcher:
    def __init__(self) -> None:
        self.security_digest: dict | None = None
        self.usb_pending_last: int = -1
        self.usb_state_last: dict | None = None
        self.usb_state_age_seen: float = 0.0

    def send(self, title: str, body: str, source: str, priority: str = "normal") -> None:
        try:
            subprocess.run(
                ["kidulwm-control", "notification_test", title, body, source, priority, source],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                check=True,
            )
        except subprocess.CalledProcessError as e:
            print(f"failed to send notification: {e.stderr.decode('utf-8', errors='replace')}", file=sys.stderr)
        except FileNotFoundError:
            print("kidulwm-control not found in PATH", file=sys.stderr)

    def check_security(self) -> None:
        if not SECURITY_STATE.exists():
            return
        try:
            data = json.loads(SECURITY_STATE.read_text())
        except Exception:
            return

        # Digest the fields we care about, ignoring the timestamp.
        digest = {
            "failed_ssh_15m": data.get("failed_ssh_15m", 0) or 0,
            "blocked_ips": data.get("blocked_ips", 0) or 0,
            "high_risk_downloads": data.get("high_risk_downloads", 0) or 0,
        }

        if self.security_digest is None:
            self.security_digest = digest
            return

        if digest != self.security_digest:
            old = self.security_digest
            parts = []
            if digest["failed_ssh_15m"] > old["failed_ssh_15m"]:
                parts.append(f"{digest['failed_ssh_15m']} SSH failures")
            if digest["blocked_ips"] > old["blocked_ips"]:
                parts.append(f"{digest['blocked_ips']} blocked IPs")
            if digest["high_risk_downloads"] > old["high_risk_downloads"]:
                parts.append(f"{digest['high_risk_downloads']} risky downloads")
            if not parts:
                parts.append("security state changed")
            self.send("Security", ", ".join(parts), "security", "critical")
            self.security_digest = digest

    def check_usb(self) -> None:
        pending_count = 0
        first_sysname = ""
        if USB_PENDING.exists():
            try:
                for line in USB_PENDING.read_text().splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    obj = json.loads(line)
                    if pending_count == 0:
                        first_sysname = obj.get("sysname", "")
                    pending_count += 1
            except Exception:
                pass

        if pending_count != self.usb_pending_last:
            if pending_count == 0:
                self.send("USB", "All pending devices cleared", "usb", "normal")
            else:
                sysname_text = f" ({first_sysname})" if first_sysname else ""
                plural = "s" if pending_count > 1 else ""
                self.send("USB", f"{pending_count} device{plural} pending approval{sysname_text}", "usb", "critical")
            self.usb_pending_last = pending_count

        if USB_STATE.exists():
            try:
                data = json.loads(USB_STATE.read_text())
            except Exception:
                return
            state_tuple = (data.get("status"), data.get("sysname"))
            now = time.time()
            if self.usb_state_last is None:
                self.usb_state_last = {"status": state_tuple, "at": data.get("at", now)}
                return

            prev_status = self.usb_state_last["status"][0]
            ts = data.get("at", now)
            # Avoid repeating the same connected/blocked event; only notify once per file write cycle.
            if state_tuple != self.usb_state_last["status"] and now - self.usb_state_age_seen > 2.0:
                status = data.get("status") or "unknown"
                sysname = data.get("sysname") or ""
                sysname_text = f" ({sysname})" if sysname else ""
                if status == "connected":
                    self.send("USB", f"Device connected{sysname_text}", "usb", "high")
                elif status == "blocked":
                    self.send("USB", f"Device blocked{sysname_text}", "usb", "critical")
                elif status != prev_status:
                    self.send("USB", f"USB {status}{sysname_text}", "usb", "high")
                self.usb_state_last = {"status": state_tuple, "at": ts}
                self.usb_state_age_seen = now
            else:
                self.usb_state_last["at"] = ts

    def run(self) -> None:
        print("kidulwm-system-watcher running", file=sys.stderr, flush=True)
        while True:
            self.check_security()
            self.check_usb()
            time.sleep(CHECK_INTERVAL)


if __name__ == "__main__":
    Watcher().run()

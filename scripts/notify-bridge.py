#!/usr/bin/env python3
"""KidulWM D-Bus notification bridge.

Implements org.freedesktop.Notifications on the session bus and forwards
every Notify call into KidulWM via its existing kidulwm-control IPC.

Install:
    cp scripts/notify-bridge.py /usr/local/bin/kidulwm-notify-bridge
    cp config/systemd/user/kidulwm-notify-bridge.service ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now kidulwm-notify-bridge

Test:
    notify-send "Hello" "This came through the bridge"
"""

import os
import subprocess
import sys

import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

BUS_NAME = "org.freedesktop.Notifications"
OBJECT_PATH = "/org/freedesktop/Notifications"
INTERFACE = "org.freedesktop.Notifications"


def forward_to_kidulwm(title: str, body: str, source: str, priority: str | None = None, action_id: str | None = None) -> None:
    """Send one notification into KidulWM's tray queue."""
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")
    sock = os.path.join(runtime, "kidulwm-control.sock")
    if not os.path.exists(sock):
        print(f"kidulwm socket missing: {sock}", file=sys.stderr)
        return
    try:
        cmd = ["kidulwm-control", "notification_test", title, body, source]
        if priority:
            cmd.append(priority)
            if action_id:
                cmd.append(action_id)
        subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        print(f"kidulwm-control failed: {e.stderr.decode('utf-8', errors='replace')}", file=sys.stderr)
    except FileNotFoundError:
        print("kidulwm-control not found in PATH", file=sys.stderr)


class Notifications(dbus.service.Object):
    def __init__(self, bus: dbus.SessionBus, bus_name: dbus.service.BusName) -> None:
        super().__init__(bus, OBJECT_PATH)
        self._bus_name = bus_name
        self._next_id = 1

    @dbus.service.method(INTERFACE, in_signature="susssasa{sv}i", out_signature="u")
    def Notify(
        self,
        app_name: str,
        replaces_id: int,
        app_icon: str,
        summary: str,
        body: str,
        actions: list,
        hints: dict,
        expire_timeout: int,
    ) -> int:
        title = summary.strip() or (app_name.strip() or "Notification")
        clean_body = body.strip()
        source = app_name.strip() or "unknown"
        priority = hints.get("urgency", None)
        if priority is not None:
            try:
                level = int(priority)
                if level == 2:
                    priority = "critical"
                elif level == 1:
                    priority = "normal"
                elif level == 0:
                    priority = "low"
                else:
                    priority = None
            except (ValueError, TypeError):
                priority = str(priority) if str(priority) else None
        action_id = hints.get("kidulwm-action", source if source in ("security", "usb") else None)
        if action_id is not None:
            action_id = str(action_id)
        forward_to_kidulwm(title, clean_body, source, priority, action_id)
        return replaces_id if replaces_id else self._next_id

    @dbus.service.method(INTERFACE, in_signature="", out_signature="as")
    def GetCapabilities(self) -> list:
        return []

    @dbus.service.method(INTERFACE, in_signature="", out_signature="ssss")
    def GetServerInformation(self) -> tuple:
        return ("kidulwm-notify-bridge", "kidulwm", "1.0", "1.2")

    @dbus.service.method(INTERFACE, in_signature="u", out_signature="")
    def CloseNotification(self, notification_id: int) -> None:
        pass


if __name__ == "__main__":
    DBusGMainLoop(set_as_default=True)

    try:
        bus = dbus.SessionBus()
    except Exception as e:
        print(f"failed to connect to session bus: {e}", file=sys.stderr)
        sys.exit(1)

    bus_name = dbus.service.BusName(BUS_NAME, bus, replace_existing=True)
    notifier = Notifications(bus, bus_name)

    print("kidulwm-notify-bridge running", file=sys.stderr, flush=True)
    GLib.MainLoop().run()

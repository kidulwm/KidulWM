#!/usr/bin/env python3
"""Lightweight GTK4 settings panel for KidulWM.

Runs as a plain GTK4 client of a KidulWM compositor.  A compact panel shows the
current matrix state and exposes IPC controls for layout/splits/gap.

Layer-shell mode is opt-in only (set ``KIDUL_TRAY_USE_LAYER=1``), because the
KidulWM compositor's layer-shell path is still under heavy test and plain GTK4
starts faster and is more stable on this host.
"""
import json
import os
import socket
import sys

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, GLib

try:
    gi.require_version("Gtk4LayerShell", "1.0")
    from gi.repository import Gtk4LayerShell

    LAYER_SHELL_AVAILABLE = True
except (ImportError, ValueError):
    LAYER_SHELL_AVAILABLE = False

# Default to plain GTK4 for startup speed and stability.  Layer-shell is opt-in.
USE_LAYER_SHELL = (
    LAYER_SHELL_AVAILABLE
    and os.environ.get("KIDUL_TRAY_USE_LAYER") == "1"
    and os.environ.get("KIDUL_TRAY_NO_LAYER") != "1"
)

IPC_SOCK = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000"), "kidulwm-control.sock"
)

def ipc_request(req: dict) -> dict:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(2)
        s.connect(IPC_SOCK)
        s.sendall((json.dumps(req) + "\n").encode())
        return json.loads(s.recv(4096).decode().strip())


class KidulTray(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="KidulWM")
        self.set_default_size(220, 400)

        if USE_LAYER_SHELL:
            Gtk4LayerShell.init_for_window(self)
            Gtk4LayerShell.set_layer(self, Gtk4LayerShell.Layer.TOP)
            Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.LEFT, True)
            Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.TOP, True)
            Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.BOTTOM, True)
            Gtk4LayerShell.set_margin(self, Gtk4LayerShell.Edge.TOP, 8)
            Gtk4LayerShell.set_margin(self, Gtk4LayerShell.Edge.BOTTOM, 8)
            Gtk4LayerShell.set_margin(self, Gtk4LayerShell.Edge.LEFT, 8)
            Gtk4LayerShell.set_exclusive_zone(self, 220)

        # Keep the panel dark like the Hermes/KidulWM chrome.
        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(
            b"window { background: #222425; color: #eeeeee; }"
            b"button { background: #2a2c2d; color: #eeeeee; border-radius: 4px; }"
            b"label { color: #eeeeee; }"
        )
        Gtk.StyleContext.add_provider_for_display(
            self.get_display(), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)
        self.set_child(box)

        title = Gtk.Label()
        title.set_markup("<b>KidulWM</b>")
        title.set_xalign(0.5)
        box.append(title)

        self.state_label = Gtk.Label()
        self.state_label.set_xalign(0.0)
        self.state_label.set_wrap(True)
        box.append(self.state_label)

        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        box.append(sep)

        box.append(self._button("Split Left", {"split_left": {}}))
        box.append(self._button("Split Right", {"split_right": {}}))
        box.append(self._button("Split Top", {"split_top": {}}))
        box.append(self._button("Split Bottom", {"split_bottom": {}}))

        gap_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        gap_box.append(Gtk.Label(label="Gap:"))
        self.gap_spin = Gtk.SpinButton.new_with_range(0, 64, 1)
        self.gap_spin.set_value(8)
        self.gap_spin.connect("value-changed", self._on_gap_changed)
        gap_box.append(self.gap_spin)
        box.append(gap_box)

        box.append(self._button("Ping", {"ping": {}}))

        GLib.timeout_add_seconds(1, self._refresh)
        self._refresh()

    def _button(self, label, req):
        btn = Gtk.Button(label=label)
        btn.connect("clicked", lambda _b: self._send(req))
        return btn

    def _send(self, req):
        try:
            resp = ipc_request(req)
            print(json.dumps(resp, indent=2))
        except Exception as e:
            print(f"IPC error: {e}", file=sys.stderr)

    def _on_gap_changed(self, spin):
        gap = int(spin.get_value())
        self._send({"set_gap": {"gap": gap}})

    def _refresh(self):
        try:
            resp = ipc_request({"get_layout": {}})
            if resp.get("ok") and resp.get("layout"):
                layout = resp["layout"]
                text = (
                    f"orientation: {layout['orientation']}\n"
                    f"gap: {layout['gap']}\n"
                    f"focus: {layout['focus']:.2f}\n"
                    f"focused: {layout['focused_window']}\n"
                    f"windows: {layout['window_count']}"
                )
                self.state_label.set_text(text)
            else:
                self.state_label.set_text("no layout")
        except Exception as e:
            self.state_label.set_text(f"error: {e}")
        return True


def main():
    app = Gtk.Application(application_id="com.kidulwm.tray")
    app.connect("activate", lambda a: KidulTray(a).present())
    sys.exit(app.run(sys.argv))


if __name__ == "__main__":
    main()

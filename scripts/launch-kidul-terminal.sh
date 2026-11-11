#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# KidulWM terminal launcher — THE terminal (Card 1.5: one terminal concept).
# ktty is our TTY; ghostty is gone (no fallback, no echo). Identity
# (WAYLAND_DISPLAY, XDG_RUNTIME_DIR) is inherited from the compositor,
# never re-typed here. Terminfo (xterm-ghostty) is embedded in the ktty
# binary; no GHOSTTY_RESOURCES_DIR, no external resource tree.
exec /usr/local/bin/ktty "$@"

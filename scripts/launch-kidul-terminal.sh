#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# KidulWM terminal launcher — THE terminal (Card 1.5: one terminal concept).
# The tentacle carries its own needs here; identity (WAYLAND_DISPLAY,
# XDG_RUNTIME_DIR) and CSD policy (GTK_CSD) are inherited from the
# compositor, never re-typed in this file.
export GHOSTTY_RESOURCES_DIR="${GHOSTTY_RESOURCES_DIR:-/usr/share/ghostty}"
exec /usr/bin/ghostty "$@"

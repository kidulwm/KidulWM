// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");
const linux = std.os.linux;
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");
const Server = @import("../server.zig").Server;

const c_std = @cImport({
    @cInclude("stdlib.h");
});

const KeyboardDevice = struct {
    manager: *KeyboardManager,
    keyboard: *wlr.Keyboard,
    input_device: *wlr.InputDevice,
    link: wl.list.Link,

    key: wl.Listener(*wlr.Keyboard.event.Key),
    modifiers: wl.Listener(*wlr.Keyboard),
    device_destroy: wl.Listener(*wlr.InputDevice),

    fn create(
        manager: *KeyboardManager,
        keyboard: *wlr.Keyboard,
        input_device: *wlr.InputDevice,
        allocator: std.mem.Allocator,
    ) !*KeyboardDevice {
        const device = try allocator.create(KeyboardDevice);
        device.* = .{
            .manager = manager,
            .keyboard = keyboard,
            .input_device = input_device,
            .link = undefined,
            .key = wl.Listener(*wlr.Keyboard.event.Key).init(handleKey),
            .modifiers = wl.Listener(*wlr.Keyboard).init(handleModifiers),
            .device_destroy = wl.Listener(*wlr.InputDevice).init(handleDestroy),
        };
        device.key.link.init();
        device.modifiers.link.init();
        device.device_destroy.link.init();
        device.link.init();

        keyboard.events.key.add(&device.key);
        keyboard.events.modifiers.add(&device.modifiers);
        input_device.events.destroy.add(&device.device_destroy);

        manager.devices.append(device);
        return device;
    }

    fn destroy(self: *KeyboardDevice) void {
        // wlr_keyboard_finish (0.20) ASSERTS events.key/modifiers/keymap/
        // repeat_info listener lists are empty — it does NOT clean them.
        // Detach every listener we registered or the compositor aborts
        // (SIGABRT) on any keyboard hot-unplug, e.g. a Bluetooth mouse
        // flapping its HID keyboard interface mid-session.
        self.key.link.remove();
        self.modifiers.link.remove();
        self.device_destroy.link.remove();
        // If this was the elected seat keyboard, drop it — the next key event
        // from any surviving device re-elects.
        if (self.manager.server.seat.getKeyboard() == self.keyboard) {
            self.manager.server.seat.setKeyboard(null);
            std.log.info("KidulWM: seat keyboard removed, awaiting re-election", .{});
        }
        self.link.remove();
        self.manager.server.input_device_counts.keyboard -|= 1;
        self.manager.server.allocator.destroy(self);
    }

    fn handleDestroy(listener: *wl.Listener(*wlr.InputDevice), input_device: *wlr.InputDevice) void {
        const self: *KeyboardDevice = @fieldParentPtr("device_destroy", listener);
        _ = input_device;
        self.destroy();
    }

    fn handleKey(listener: *wl.Listener(*wlr.Keyboard.event.Key), event: *wlr.Keyboard.event.Key) void {
        const self: *KeyboardDevice = @fieldParentPtr("key", listener);
        const server = self.manager.server;
        // Seat election: the first keyboard that actually emits an event
        // becomes the seat keyboard; if the elected device later vanishes
        // (device_destroy clears it), the next event re-elects. A virtual
        // or control-only keyboard that never fires can never win.
        if (server.seat.getKeyboard() != self.keyboard) {
            server.seat.setKeyboard(self.keyboard);
            std.log.info("KidulWM: seat keyboard elected: {s}", .{self.input_device.name orelse "?"});
        }
        // smartLock: every key event (press OR release) counts as activity.
        server.noteInputActivity();

        const keyboard = server.seat.getKeyboard() orelse {
            server.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
            return;
        };
        const state = keyboard.xkb_state orelse {
            server.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
            return;
        };
        const sym = xkb.State.keyGetOneSym(state, event.keycode + 8);
        // For keybind matching with Ctrl, we need the base keysym without Ctrl applied.
        // keyGetOneSym with Ctrl held returns a control char (e.g. Ctrl+Q = 0x11), not the letter.
        // Map control chars back to their letter for keybind matching.
        var base_sym = sym;
        const sym_val: u32 = @intFromEnum(sym);
        if (sym_val >= 0x01 and sym_val <= 0x1a) {
            // Ctrl+A..Z maps to 0x01..0x1a — convert back to letter keysym.
            base_sym = @enumFromInt(@as(u32, @intCast('a')) + (sym_val - 0x01));
        }
        const mod4_active = xkb.State.modNameIsActive(
            state,
            "Mod4",
            @as(xkb.State.Component, @enumFromInt(xkb.State.Component.mods_depressed)),
        ) > 0;
        const ctrl_active = xkb.State.modNameIsActive(
            state,
            "Control",
            @as(xkb.State.Component, @enumFromInt(xkb.State.Component.mods_depressed)),
        ) > 0;

        // GRACE PERIOD (fadeOutOfExistence → fadeIntoExistence). While the
        // screen is off, or inside the post-wake gracePeriod, swallow every
        // key event (press AND release): a black screen reads as "locked",
        // so a password typed at it — or an accidental two-key mash — is
        // discarded, never forwarded to the focused slide. Blind-safe
        // media/volume keys still fire while OFF (sound-only, granny can
        // hear the result); a release never wakes.
        if (server.screens_off) {
            if (event.state == .pressed and !mod4_active and !ctrl_active and isBlindSafeKeysym(sym)) {
                std.log.info("KidulWM: blind-first-press sym=0x{x} (screen stays off)", .{@intFromEnum(sym)});
                if (handleBlindSafeKeysym(server, sym)) return;
                // fell through (no handler for that keysym) → wake below
            }
            if (event.state == .pressed) {
                server.screensOffSet(false); // fadeIntoExistence
                server.beginInputGrace(); // gracePeriod: swallow-all
            }
            return;
        }
        if (server.inInputGrace()) return; // gracePeriod: discard until settled

        if (event.state != .pressed) {
            server.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
            return;
        }
        // Volume keys work sighted too — they're bound unmodified so the
        // remote's buttons hit them without Mod4. Intercept before the
        // Mod4/Ctrl bind match (which never fires for bare keysyms).
        if (!mod4_active and !ctrl_active and isBlindSafeKeysym(sym)) {
            if (handleBlindSafeKeysym(server, sym)) return;
        }
        // Remote HOME (back-home.md): the SW button below the crosspad sends
        // the standard XF86HomePage keysym — the remote's "back to home", the
        // same verb as Mod4+Q close_focused. Unmodified, like the volume keys.
        if (!mod4_active and !ctrl_active and sym == xkb.Keysym.XF86HomePage) {
            if (handleAction(server, .close_focused)) return;
        }
        if (mod4_active or ctrl_active) {
            // The media PLAYER is a real deck slide now (TASKCARD-3):
            // Ctrl+Q falls through to close_focused like any slide.
            const action = server.keybinds.match(mod4_active, ctrl_active, base_sym);
            if (action) |a| {
                server.recordKeyEvent(@intFromEnum(base_sym), mod4_active, ctrl_active, @tagName(a));
                if (handleAction(server, a)) return;
            } else {
                server.recordKeyEvent(@intFromEnum(base_sym), mod4_active, ctrl_active, "no_match");
            }
        }
        // Overview slide owns Esc/Enter/arrows while open. Scan every
        // output's deck — the overview may be open on a deck that isn't
        // "current" by keyboard focus.
        var overview_open = server.deck.overview_slide_open;
        var oit = server.outputs.iterator(.forward);
        while (oit.next()) |output| {
            if (output.deck.overview_slide_open) overview_open = true;
        }
        if (overview_open) {
            switch (sym) {
                xkb.Keysym.Escape => {
                    // Esc = close, return to the slide that opened it.
                    server.overviewToggle();
                    return;
                },
                xkb.Keysym.Return, xkb.Keysym.KP_Enter => {
                    server.overviewAcceptFocused();
                    return;
                },
                xkb.Keysym.Left => {
                    server.overviewMoveCursor(-1);
                    return;
                },
                xkb.Keysym.Right => {
                    server.overviewMoveCursor(1);
                    return;
                },
                xkb.Keysym.Up => {
                    server.overviewMoveCursor(-2);
                    return;
                },
                xkb.Keysym.Down => {
                    server.overviewMoveCursor(2);
                    return;
                },
                else => {
                    server.recordKeyEvent(@intFromEnum(sym), mod4_active, ctrl_active, "swallowed:overview");
                    return; // swallow all other keys while the grid is open
                },
            }
        }
        // Media player slide owns keys while focused on this deck (a real
        // deck slide, TASKCARD-3). INPUT LAW: ↑↓=focus, ←→=move, Enter=apply,
        // Esc=back. NOTHING SWALLOWED: unconsumed keys fall through to
        // normal routing.
        if (server.currentDeckPub().findKind(.media_player) != null) {
            if (server.mediaSlideKey(sym)) return;
            // fall through — no swallow
        }
        server.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
    }

    /// Blind-safe keysyms: actions that change SOUND, not SIGHT. Safe to run
    /// with the screen black because granny can hear the result.
    fn isBlindSafeKeysym(sym: xkb.Keysym) bool {
        return switch (sym) {
            xkb.Keysym.XF86AudioPlay,
            xkb.Keysym.XF86AudioPause,
            xkb.Keysym.XF86AudioStop,
            xkb.Keysym.XF86AudioNext,
            xkb.Keysym.XF86AudioPrev,
            xkb.Keysym.XF86AudioForward,
            xkb.Keysym.XF86AudioRewind,
            xkb.Keysym.XF86AudioRaiseVolume,
            xkb.Keysym.XF86AudioLowerVolume,
            xkb.Keysym.XF86AudioMute,
            => true,
            else => false,
        };
    }

    /// Execute a blind-safe action against the single session player. The
    /// screen stays OFF — the whole point. Returns false if nothing handled
    /// the keysym (caller then treats the press as a plain wake).
    fn handleBlindSafeKeysym(server: *Server, sym: xkb.Keysym) bool {
        switch (sym) {
            xkb.Keysym.XF86AudioPlay, xkb.Keysym.XF86AudioPause => {
                server.kplayTogglePause();
                return true;
            },
            xkb.Keysym.XF86AudioNext => {
                return true;
            },
            xkb.Keysym.XF86AudioPrev => {
                return true;
            },
            xkb.Keysym.XF86AudioForward => {
                server.kplaySeekRel(10.0);
                return true;
            },
            xkb.Keysym.XF86AudioRewind => {
                server.kplaySeekRel(-10.0);
                return true;
            },
            xkb.Keysym.XF86AudioStop => {
                server.kplayStop();
                return true;
            },
            xkb.Keysym.XF86AudioRaiseVolume => {
                server.volumeStep(0.05);
                return true;
            },
            xkb.Keysym.XF86AudioLowerVolume => {
                server.volumeStep(-0.05);
                return true;
            },
            xkb.Keysym.XF86AudioMute => {
                server.volumeToggleMute();
                return true;
            },
            else => return false,
        }
    }

    fn handleAction(server: *Server, action: @import("../config/keybinds.zig").Action) bool {
        switch (action) {
            .spawn => |cmd| {
                // EPHEMERAL LAW: a spawn while the home slide holds this row
                // self-ejects it (successful launch = home destroys itself).
                server.homeSlideLaunch(cmd);
                return true;
            },
            .focus_next => {
                server.focusNext();
                return true;
            },
            .focus_prev => {
                server.focusPrev();
                return true;
            },
            .tray_toggle => {
                // Tray-slide birth (stage 1): the tray overlay is dead as a
                // keybind target — focus the home slide, or spawn one at
                // before_first if this row has none (A7).
                server.homeSlideFocusOrSpawn();
                return true;
            },
            .tray_select_next => {
                server.focusNext();
                return true;
            },
            .tray_select_prev => {
                server.focusPrev();
                return true;
            },
            .tray_activate => {
                // The old "open the highlighted tray row" — with the tray
                // gone, activating IS opening the overview pick (Mod4+space).
                server.overviewToggle();
                return true;
            },
            .media_card_toggle => {
                // REDIRECT (TASKCARD-3): focus-or-spawn the media player
                // slide (a real deck slide).
                server.mediaSlideFocusOrSpawn();
                return true;
            },
            .signals_card_toggle => {
                // Kill orphans from a previous compositor session, then spawn
                _ = c_std.system("pkill -9 ksignals 2>/dev/null; sleep 0.2");
                server.spawnCommand("/usr/local/bin/ksignals");
                return true;
            },
            .next_animation => {
                server.nextAnimationKind();
                return true;
            },
            .close_focused => {
                // Stock quit on the focused slide (A7): compositor-owned
                // slides destroy themselves through the same door as client
                // windows — no overview bookkeeping.
                const deck = server.currentDeckPub();
                if (deck.empty_slot == .none and deck.focused_index < deck.slides.items.len) {
                    const slide = deck.slides.items[deck.focused_index];
                    switch (slide.kind) {
                        .home => {
                            server.homeSlideClose();
                            return true;
                        },
                        .media_player => {
                            // fullscreen.md: close card = QUIT. If the video is
                            // up, exit fullscreen first (fade out + teardown,
                            // sound dies), then close the card.
                            if (server.video_fullscreen) server.videoFullscreenExit();
                            server.mediaSlideClose();
                            return true;
                        },
                        .app => {},
                    }
                }
                if (server.focused_window) |win| {
                    win.toplevel.sendClose();
                }
                return true;
            },
            .reload => {
                server.requestQuit();
                return true;
            },
            .wm_reset => {
                // Soft WM reset (i3/sway style). Validate outputs.toml first —
                // a broken config surfaces as a HIGH notification in the
                // home-slide feed and the live layout is left untouched.
                var v = @import("../core/output_layout_config.zig").validate(server.allocator);
                if (!v.ok()) {
                    server.notificationAdd("WM reset blocked", v.problems.items[0], "kidulwm", "high", null, null);
                    return true;
                }
                server.arrangeOutputsLive();
                server.notificationAdd("WM reset", "outputs re-arranged from outputs.toml", "kidulwm", "low", null, null);
                return true;
            },
            .park_toggle => {
                server.parkToggleFocused();
                return true;
            },
            .overview_toggle => {
                server.overviewToggle();
                return true;
            },
            .focus_output_next => {
                server.focusOutputNext();
                return true;
            },
            .move_to_output_next => {
                server.moveFocusedToOutputNext();
                return true;
            },
            .fullscreen_toggle => {
                server.fullscreenToggleFocused();
                return true;
            },
            .screen_off => {
                server.screensOffToggle();
                return true;
            },
            .volume_up => {
                server.volumeStep(0.05);
                return true;
            },
            .volume_down => {
                server.volumeStep(-0.05);
                return true;
            },
            .volume_mute => {
                server.volumeToggleMute();
                return true;
            },
            .none => return false,
        }
    }

    fn handleModifiers(listener: *wl.Listener(*wlr.Keyboard), keyboard: *wlr.Keyboard) void {
        const self: *KeyboardDevice = @fieldParentPtr("modifiers", listener);
        self.manager.server.seat.keyboardNotifyModifiers(&keyboard.modifiers);
    }
};

pub const KeyboardManager = struct {
    server: *Server,
    devices: wl.list.Head(KeyboardDevice, .link),

    pub fn init(self: *KeyboardManager, server: *Server) void {
        self.* = .{
            .server = server,
            .devices = undefined,
        };
        self.devices.init();
    }

    pub fn listen(self: *KeyboardManager, keyboard: *wlr.Keyboard, input_device: *wlr.InputDevice) void {
        _ = KeyboardDevice.create(self, keyboard, input_device, self.server.allocator) catch |err| {
            std.log.err("failed to allocate keyboard device state: {}", .{err});
        };
    }

    pub fn deinit(self: *KeyboardManager) void {
        while (self.devices.first()) |device| {
            device.destroy();
        }
    }
};

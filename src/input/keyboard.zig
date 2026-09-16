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
        if (event.state != .pressed) {
            server.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
            return;
        }
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

        if (mod4_active or ctrl_active) {
            // Media slide owns Ctrl+Q (system quit) while open on the
            // focused deck: closing the slide IS closing the focused surface.
            // The media slide is a normal deck slide (media-is-a-slide.md) —
            // no sentinel, just the deck flag.
            if (server.currentDeckPub().media_slide_open and ctrl_active and base_sym == xkb.Keysym.q) {
                server.recordKeyEvent(@intFromEnum(base_sym), mod4_active, ctrl_active, "media_slide_ctrl_q");
                server.mediaSlideToggle();
                return;
            }
            const action = server.keybinds.match(mod4_active, ctrl_active, base_sym);
            if (action) |a| {
                server.recordKeyEvent(@intFromEnum(base_sym), mod4_active, ctrl_active, @tagName(a));
                if (handleAction(server, a)) return;
            } else {
                server.recordKeyEvent(@intFromEnum(base_sym), mod4_active, ctrl_active, "no_match");
            }
        }
        // Overview sentinel owns Esc/Enter/arrows while open. Scan every
        // output's deck — the sentinel may be open on a deck that isn't
        // "current" by keyboard focus.
        var sentinel_open = server.deck.overview_slide_open;
        var oit = server.outputs.iterator(.forward);
        while (oit.next()) |output| {
            if (output.deck.overview_slide_open) sentinel_open = true;
        }
        if (sentinel_open) {
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
        // Media slide owns keys while open on the focused deck (a normal
        // deck slide per media-is-a-slide.md). INPUT LAW: ↑↓=focus, ←→=move,
        // Enter=apply, Esc=back. NOTHING SWALLOWED: unconsumed keys fall
        // through to normal routing (card phase 2).
        if (server.currentDeckPub().media_slide_open) {
            if (server.mediaSlideKey(sym)) return;
            // fall through — no swallow
        }
        // Cards consume arrow/navigation/typing before clients while open.
        // NOTE: media_card_open deliberately EXCLUDED — the media player is
        // a deck slide now; the dead card flag must never swallow keys.
        if (server.tray.calendar_card_open or server.tray.weather_card_open or server.tray.files_card_open) {
            if (server.tray.handleMediaCardKey(sym)) return;
            if (server.tray.handleFilesCardKey(sym)) return;
            if (server.tray.handleCalendarCardKey(sym)) return;
            if (server.tray.handleWeatherCardKey(sym)) return;
            // With a card open and no card handler consumed it, do not pass to clients;
            // this keeps arrow keys from moving a focused window while navigating the card.
            server.recordKeyEvent(@intFromEnum(sym), mod4_active, ctrl_active, "swallowed:card");
            return;
        }
        // Tray takes full keyboard control while open (arrows to navigate, Return to activate, Escape to close).
        if (server.tray.isOpen()) {
            switch (sym) {
                xkb.Keysym.Up => {
                    server.tray.selectPrev();
                    return;
                },
                xkb.Keysym.Down => {
                    server.tray.selectNext();
                    return;
                },
                xkb.Keysym.Return, xkb.Keysym.KP_Enter => {
                    server.tray.activateSelected();
                    return;
                },
                xkb.Keysym.Escape => {
                    server.tray.toggle();
                    return;
                },
                else => {},
            }
        }
        server.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
    }

    fn handleAction(server: *Server, action: @import("../config/keybinds.zig").Action) bool {
        switch (action) {
            .spawn => |cmd| {
                server.spawnCommand(cmd);
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
            .media_card_toggle => {
                // Same target for now (stage 1): focus/spawn the home slide.
                // The real media readout section is a later stage.
                server.homeSlideFocusOrSpawn();
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
                // A7: the home slide is QUITABLE — the standard quit keybind
                // closes it like any slide (instead of killing a client) when
                // focus rests on the home sentinel slot.
                const deck = server.currentDeckPub();
                if (deck.homeSlideOpen()) {
                    server.homeSlideClose();
                    return true;
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
                // a broken config surfaces as a HIGH notification in the right
                // peek and the live layout is left untouched.
                var v = @import("../core/output_layout_config.zig").validate(server.allocator);
                if (!v.ok()) {
                    server.tray.notificationAdd("WM reset blocked", v.problems.items[0], "kidulwm", "high", null, null);
                    return true;
                }
                server.arrangeOutputsLive();
                server.tray.notificationAdd("WM reset", "outputs re-arranged from outputs.toml", "kidulwm", "low", null, null);
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

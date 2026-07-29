const std = @import("std");
const linux = std.os.linux;
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");
const Server = @import("../server.zig").Server;

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
        // The input device and its signals are being destroyed; wlroots cleans
        // its own signal lists, so only detach from the manager list here.
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
        const mod4_active = xkb.State.modNameIsActive(
            state,
            "Mod4",
            @as(xkb.State.Component, @enumFromInt(xkb.State.Component.mods_depressed)),
        ) > 0;

        if (mod4_active) {
            const action = server.keybinds.match(true, sym);
            if (action) |a| {
                if (handleAction(server, a)) return;
            }
        }
        // Cards consume arrow/navigation/typing before clients while open.
        if (server.tray.calendar_card_open or server.tray.weather_card_open or server.tray.media_card_open) {
            if (server.tray.handleMediaCardKey(sym)) return;
            if (server.tray.handleCalendarCardKey(sym)) return;
            if (server.tray.handleWeatherCardKey(sym)) return;
            // With a card open and no card handler consumed it, do not pass to clients;
            // this keeps arrow keys from moving a focused window while navigating the card.
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
                server.tray.toggle();
                return true;
            },
            .tray_select_next => {
                if (server.tray.isOpen()) server.tray.selectPrev() else server.tray.toggle();
                return true;
            },
            .tray_select_prev => {
                if (server.tray.isOpen()) server.tray.selectNext() else server.tray.toggle();
                return true;
            },
            .tray_activate => {
                if (server.tray.isOpen()) server.tray.activateSelected() else server.tray.toggle();
                return true;
            },
            .media_card_toggle => {
                server.tray.toggleMediaCard();
                return true;
            },
            .next_animation => {
                server.nextAnimationKind();
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

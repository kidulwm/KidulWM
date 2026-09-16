const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const Server = @import("server.zig").Server;
const Window = @import("window.zig").Window;

pub const InputManager = struct {
    server: *Server,

    new_input: wl.Listener(*wlr.InputDevice),
    request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor),

    pub fn init(self: *InputManager, server: *Server) void {
        self.* = .{
            .server = server,
            .new_input = wl.Listener(*wlr.InputDevice).init(handleNewInput),
            .request_set_cursor = wl.Listener(*wlr.Seat.event.RequestSetCursor).init(handleRequestSetCursor),
        };
        self.new_input.link.init();
        self.request_set_cursor.link.init();
        server.backend.events.new_input.add(&self.new_input);
        server.seat.events.request_set_cursor.add(&self.request_set_cursor);
    }

    pub fn deinit(self: *InputManager) void {
        self.request_set_cursor.link.remove();
        self.new_input.link.remove();
    }

    fn handleNewInput(listener: *wl.Listener(*wlr.InputDevice), device: *wlr.InputDevice) void {
        const self: *InputManager = @fieldParentPtr("new_input", listener);

        switch (device.type) {
            .keyboard => {
                const keyboard = device.toKeyboard();
                self.configureKeyboard(keyboard);
                self.server.keyboard.listen(keyboard, device);
                // Do NOT setKeyboard here. Host libinput presents many
                // keyboard-class devices (keyd virtual keyboard, control
                // interfaces, mouse HID keyboards); last attach wins and a
                // silent device can steal the seat. Election happens on the
                // first real key event instead (keyboard.zig handleKey).
                self.server.input_device_counts.keyboard += 1;
                std.log.info("KidulWM: keyboard device attached: {s}", .{device.name orelse "?"});
            },
            .pointer => {
                const pointer = device.toPointer();
                self.server.pointer.listen(pointer, device);
                self.server.cursor.attachInputDevice(device);
                self.server.input_device_counts.pointer += 1;
                std.log.info("KidulWM: pointer device discovered", .{});
            },
            else => {},
        }
        self.server.requestUpdateCapabilities();
    }

    fn configureKeyboard(self: *InputManager, keyboard: *wlr.Keyboard) void {
        _ = self;
        const context = xkb.Context.new(.no_flags) orelse return;
        defer context.unref();

        const rule_names = xkb.RuleNames{
            .rules = null,
            .model = null,
            .layout = null,
            .variant = null,
            .options = null,
        };
        const keymap = xkb.Keymap.newFromNames(context, &rule_names, .no_flags) orelse {
            std.log.warn("KidulWM: failed to create default keymap", .{});
            return;
        };
        defer keymap.unref();

        if (!keyboard.setKeymap(keymap)) {
            std.log.warn("KidulWM: failed to set keymap on keyboard", .{});
        }
    }

    fn handleRequestSetCursor(
        listener: *wl.Listener(*wlr.Seat.event.RequestSetCursor),
        event: *wlr.Seat.event.RequestSetCursor,
    ) void {
        const self: *InputManager = @fieldParentPtr("request_set_cursor", listener);
        _ = event;
        // ONE CURSOR LAW (2026-09-15): the compositor owns the pointer image
        // everywhere. Clients (browser text fields, terminals) all request
        // their own shapes; we ignore every request and assert the house
        // cursor. One image, same size, no ibeam surprises.
        self.server.cursor.setXcursor(self.server.xcursor_manager, "left_ptr");
    }
};

const xkb = @import("xkbcommon");

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const Server = @import("server.zig").Server;
const Window = @import("window.zig").Window;

pub const InputManager = struct {
    server: *Server,

    new_input: wl.Listener(*wlr.InputDevice),

    pub fn init(server: *Server) InputManager {
        var manager: InputManager = .{
            .server = server,
            .new_input = undefined,
        };
        manager.new_input = wl.Listener(*wlr.InputDevice).init(handleNewInput);
        server.backend.events.new_input.add(&manager.new_input);
        return manager;
    }

    pub fn deinit(self: *InputManager) void {
        self.new_input.link.remove();
    }

    fn handleNewInput(listener: *wl.Listener(*wlr.InputDevice), device: *wlr.InputDevice) void {
        const self: *InputManager = @fieldParentPtr("new_input", listener);
        const seat = self.server.seat;

        switch (device.type) {
            .keyboard => {
                const keyboard = device.toKeyboard();
                self.configureKeyboard(keyboard);
                self.server.keyboard.listen(keyboard);
                seat.setKeyboard(keyboard);
                self.server.input_device_counts.keyboard += 1;
                std.log.info("KidulWM: keyboard attached to seat", .{});
            },
            .pointer => {
                const pointer = device.toPointer();
                self.server.pointer.listen(pointer);
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
};

const xkb = @import("xkbcommon");

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const Server = @import("../server.zig").Server;

pub const KeyboardManager = struct {
    server: *Server,

    key: wl.Listener(*wlr.Keyboard.event.Key),
    modifiers: wl.Listener(*wlr.Keyboard),

    pub fn init(server: *Server) KeyboardManager {
        return .{
            .server = server,
            .key = wl.Listener(*wlr.Keyboard.event.Key).init(handleKey),
            .modifiers = wl.Listener(*wlr.Keyboard).init(handleModifiers),
        };
    }

    pub fn listen(self: *KeyboardManager, keyboard: *wlr.Keyboard) void {
        keyboard.events.key.add(&self.key);
        keyboard.events.modifiers.add(&self.modifiers);
    }

    fn handleKey(listener: *wl.Listener(*wlr.Keyboard.event.Key), event: *wlr.Keyboard.event.Key) void {
        const self: *KeyboardManager = @fieldParentPtr("key", listener);
        // A real compositor runs xkb_state_key_get_one_sym etc. here.
        std.log.debug("KidulWM: key event keycode={d} state={}", .{ event.keycode, @intFromEnum(event.state) });
        self.server.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
    }

    fn handleModifiers(listener: *wl.Listener(*wlr.Keyboard), keyboard: *wlr.Keyboard) void {
        const self: *KeyboardManager = @fieldParentPtr("modifiers", listener);
        self.server.seat.keyboardNotifyModifiers(&keyboard.modifiers);
        _ = self.server.seat.getKeyboard();
    }
};

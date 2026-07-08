const std = @import("std");
const wl = @import("wayland").server.wl;

pub fn main() void {
    const L = wl.Listener(*u8);
    const S = wl.Signal(*u8);
    std.debug.print("Zig Listener size={} align={}\n", .{@sizeOf(L), @alignOf(L)});
    std.debug.print("Zig Listener offset notify={}\n", .{@offsetOf(L, "notify")});
    std.debug.print("Zig Signal size={} align={}\n", .{@sizeOf(S), @alignOf(S)});
    std.debug.print("Zig Signal offset listener_list={}\n", .{@offsetOf(S, "listener_list")});
}

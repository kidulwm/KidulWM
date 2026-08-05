const std = @import("std");
const kmedia = @import("core/kmedia.zig");

pub fn main(init: std.process.Init.Minimal) !void {
    _ = init;
    std.log.info("kmedia test: starting capture...", .{});
    kmedia.start();
    // Wait for connection and print band levels for ~10 seconds.
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        var ts: std.os.linux.timespec = .{ .sec = 0, .nsec = 500 * 1_000_000 };
        _ = std.os.linux.nanosleep(&ts, null);
        const b = kmedia.bands();
        std.log.info("running={} level={d:.3} bands=[{d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2}]", .{
            kmedia.isRunning(), kmedia.level(),
            b[0], b[1], b[2], b[3], b[4], b[5], b[6],
        });
    }
    kmedia.stop();
}

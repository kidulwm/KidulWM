const moon = @import("moon");

pub fn main() !void {
    try moon.renderMoonTestStrip("/tmp/moon_test.png", .{ 0.412, 0.396, 0.333, 1.0 }, .{ 0.133, 0.141, 0.145, 1.0 });
}

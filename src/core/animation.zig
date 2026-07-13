const std = @import("std");

/// Time in microseconds; matches wlroots frame loop resolution.
pub const TimeUs = u64;

/// Spring tuned for crisp, fast motion with no visible oscillation.
///   stiffness ~7 gives ~170 ms settle
///   damping ~0.95 kills overshoot on 60/144 Hz
pub const Spring = struct {
    stiffness: f64 = 7.0,
    damping: f64 = 0.95,
    epsilon: f64 = 0.5,

    /// Integrate toward target for `dt_s` seconds using semi-implicit Euler.
    /// Returns (new_value, new_velocity, settled).
    pub fn step(
        self: Spring,
        value: f64,
        velocity: f64,
        target: f64,
        dt_s: f64,
    ) struct { value: f64, velocity: f64, settled: bool } {
        const displacement = target - value;
        const accel = self.stiffness * displacement;
        const new_velocity = (velocity + accel * dt_s) * self.damping;
        const new_value = value + new_velocity * dt_s;
        const settled = @abs(displacement) < self.epsilon and @abs(new_velocity) < self.epsilon;
        return .{ .value = new_value, .velocity = new_velocity, .settled = settled };
    }
};

/// Animation state for a single window.
pub const WindowAnimation = struct {
    target_x: f64 = 0,
    target_y: f64 = 0,
    target_w: f64 = 0,
    target_h: f64 = 0,
    target_opacity: f64 = 1,

    cur_x: f64 = 0,
    cur_y: f64 = 0,
    cur_w: f64 = 0,
    cur_h: f64 = 0,
    cur_opacity: f64 = 1,

    /// Position at the start of the current transition.
    start_x: f64 = 0,
    start_y: f64 = 0,

    last_us: TimeUs = 0,

    /// 120 ms ease-out interpolation used only between SlideDeck states.
    position_duration_us: TimeUs = 120_000,
    position_ease_power: u32 = 3,

    pub fn isSettled(self: WindowAnimation) bool {
        return @abs(self.target_x - self.cur_x) < 1.0 and
            @abs(self.target_y - self.cur_y) < 1.0 and
            @abs(self.target_w - self.cur_w) < 1.0 and
            @abs(self.target_h - self.cur_h) < 1.0;
    }

    /// Interpolate position toward target over `position_duration_us`. Size and
    /// opacity snap immediately. Returns true while moving.
    pub fn tick(self: *WindowAnimation, now_us: TimeUs) bool {
        if (self.last_us == 0) {
            self.last_us = now_us;
            return false;
        }
        const elapsed = now_us - self.last_us;
        if (elapsed >= self.position_duration_us) {
            self.cur_x = self.target_x;
            self.cur_y = self.target_y;
            return false;
        }
        const t = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(self.position_duration_us));
        const eased = 1.0 - std.math.pow(f64, 1.0 - t, self.position_ease_power);
        self.cur_x = self.start_x + (self.target_x - self.start_x) * eased;
        self.cur_y = self.start_y + (self.target_y - self.start_y) * eased;
        return true;
    }
};

pub const MapAnimation = WindowAnimation;

/// Helper for compositor frame timing.
pub fn nowUs() TimeUs {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    return @as(TimeUs, @intCast(ts.sec)) * 1_000_000 + @as(TimeUs, @intCast(ts.nsec)) / 1000;
}

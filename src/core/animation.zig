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

/// Shared animation presets. One row per "class" of motion.
/// Changing a preset here changes every UI element that uses that class.
/// Fields are split into open vs close so each direction can snap or ease
/// independently.
pub const Preset = struct {
    stiffness_open: f64,
    damping_open: f64,
    stiffness_close: f64,
    damping_close: f64,
    epsilon: f64 = 0.001,
    /// Close only: fade opacity while going away.
    fade_close: bool = false,
    /// Close only: slide offset in output pixels. Negative = up/left, positive = down/right.
    /// For cards this is multiplied by a per-mode direction vector.
    slide_close_px: f32 = 0,
    /// If true, opening skips the spring and snaps to target in one frame.
    snap_open: bool = false,
    /// True for popups/cards that should stop rendering near 0.
    disable_when_closed: bool = false,

    pub fn spring(self: *const Preset, closing: bool) Spring {
        if (closing) {
            return .{ .stiffness = self.stiffness_close, .damping = self.damping_close, .epsilon = self.epsilon };
        }
        return .{ .stiffness = self.stiffness_open, .damping = self.damping_open, .epsilon = self.epsilon };
    }
};

pub const presets = struct {
    /// Tray: snap open, fade+slide closed.
    pub const tray = Preset{
        .stiffness_open = 600.0,
        .damping_open = 0.99,
        .stiffness_close = 18.0,
        .damping_close = 0.95,
        .epsilon = 0.001,
        .fade_close = true,
        .slide_close_px = 0,
        .disable_when_closed = false,
        .snap_open = true,
    };
    /// Cards: snap open, fade+slide closed toward source widget.
    pub const card = Preset{
        .stiffness_open = 1200.0,
        .damping_open = 1.0,
        .stiffness_close = 180.0,
        .damping_close = 1.0,
        .epsilon = 0.001,
        .fade_close = true,
        .slide_close_px = 60,
        .disable_when_closed = true,
        .snap_open = true,
    };
    /// Small peek widgets (weather icon, date peek).
    pub const peek = Preset{
        .stiffness_open = 60.0,
        .damping_open = 0.95,
        .stiffness_close = 8.0,
        .damping_close = 0.92,
        .epsilon = 0.001,
        .fade_close = true,
        .slide_close_px = 0,
        .disable_when_closed = false,
    };
};

/// Per-instance animated scalar. Holds runtime value/velocity and points back
/// to a shared preset.
pub const AnimatedFloat = struct {
    value: f32 = 0,
    velocity: f32 = 0,
    desired: f32 = 0,
    preset: *const Preset = &presets.tray,
    last_settled: bool = true,

    pub fn setTarget(self: *AnimatedFloat, target: f32) void {
        self.desired = target;
    }

    pub fn toggle(self: *AnimatedFloat) void {
        self.desired = if (self.desired >= 0.5) 0.0 else 1.0;
    }

    pub fn step(self: *AnimatedFloat, dt_s: f64) bool {
        if (dt_s <= 0.0) return !self.isSettled();
        const closing = self.desired < self.value;
        if (!closing and self.preset.snap_open) {
            self.value = self.desired;
            self.velocity = 0.0;
            self.last_settled = true;
            return false;
        }
        const result = self.preset.spring(closing).step(self.value, self.velocity, self.desired, dt_s);
        self.value = @floatCast(result.value);
        self.velocity = @floatCast(result.velocity);
        self.last_settled = result.settled;
        return !result.settled;
    }

    pub fn isSettled(self: *const AnimatedFloat) bool {
        return self.last_settled and @abs(self.desired - self.value) < self.preset.epsilon;
    }

    pub fn isOpen(self: *const AnimatedFloat) bool {
        return self.value >= 0.01;
    }

    pub fn isClosing(self: *const AnimatedFloat) bool {
        return self.desired < self.value;
    }
};

/// Animation state for a single window.
pub const AnimationKind = enum {
    snap,
    wobble,
    ripple,
};

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

    /// Velocity used for spring-based presets (wobble / ripple).
    vx: f64 = 0,
    vy: f64 = 0,

    kind: AnimationKind = .snap,
    start_us: TimeUs = 0,
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

    /// Interpolate position toward target. Size and opacity snap immediately.
    /// Returns true while moving.
    pub fn tick(self: *WindowAnimation, now_us: TimeUs) bool {
        if (self.start_us == 0) {
            self.start_us = now_us;
            self.last_us = now_us;
            return false;
        }
        const elapsed = now_us - self.start_us;
        switch (self.kind) {
            .snap => {
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
            },
            .wobble => {
                if (elapsed >= self.position_duration_us) {
                    // Spring got at least the minimal snap window; continue until settled.
                }
                const dt = @as(f64, @floatFromInt(now_us - self.last_us)) / 1_000_000.0;
                self.last_us = now_us;
                if (dt <= 0.0) return true;
                const spring = Spring{ .stiffness = 25.0, .damping = 0.82, .epsilon = 2.0 };
                const rx = spring.step(self.cur_x, self.vx, self.target_x, dt);
                const ry = spring.step(self.cur_y, self.vy, self.target_y, dt);
                self.cur_x = rx.value;
                self.cur_y = ry.value;
                self.vx = rx.velocity;
                self.vy = ry.velocity;
                if (rx.settled and ry.settled) {
                    self.cur_x = self.target_x;
                    self.cur_y = self.target_y;
                    return false;
                }
                return true;
            },
            .ripple => {
                const dt = @as(f64, @floatFromInt(now_us - self.last_us)) / 1_000_000.0;
                self.last_us = now_us;
                if (dt <= 0.0) return true;
                const spring = Spring{ .stiffness = 18.0, .damping = 0.90, .epsilon = 1.5 };
                const rx = spring.step(self.cur_x, self.vx, self.target_x, dt);
                const ry = spring.step(self.cur_y, self.vy, self.target_y, dt);
                self.cur_x = rx.value;
                self.cur_y = ry.value;
                self.vx = rx.velocity;
                self.vy = ry.velocity;
                if (rx.settled and ry.settled) {
                    self.cur_x = self.target_x;
                    self.cur_y = self.target_y;
                    return false;
                }
                return true;
            },
        }
    }
};

pub const MapAnimation = WindowAnimation;

/// Helper for compositor frame timing.
pub fn nowUs() TimeUs {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    return @as(TimeUs, @intCast(ts.sec)) * 1_000_000 + @as(TimeUs, @intCast(ts.nsec)) / 1000;
}

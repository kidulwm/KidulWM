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

    vx: f64 = 0,
    vy: f64 = 0,
    vw: f64 = 0,
    vh: f64 = 0,
    v_opacity: f64 = 0,

    opacity_in_spring: Spring = .{ .stiffness = 18.0, .damping = 0.92, .epsilon = 0.02 },
    motion_spring: Spring = .{ .stiffness = 7.5, .damping = 0.96, .epsilon = 0.5 },

    /// Update current values toward targets and report whether anything moved.
    pub fn tick(self: *WindowAnimation, now_us: TimeUs) bool {
        const dt_s: f64 = 1.0 / 120.0; // assume 120 Hz logic step for consistent motion
        _ = now_us;

        const px = self.motion_spring.step(self.cur_x, self.vx, self.target_x, dt_s);
        const py = self.motion_spring.step(self.cur_y, self.vy, self.target_y, dt_s);
        const pw = self.motion_spring.step(self.cur_w, self.vw, self.target_w, dt_s);
        const ph = self.motion_spring.step(self.cur_h, self.vh, self.target_h, dt_s);
        const po = self.opacity_in_spring.step(self.cur_opacity, self.v_opacity, self.target_opacity, dt_s);

        self.cur_x = px.value;
        self.vx = px.velocity;
        self.cur_y = py.value;
        self.vy = py.velocity;
        self.cur_w = pw.value;
        self.vw = pw.velocity;
        self.cur_h = ph.value;
        self.vh = ph.velocity;
        self.cur_opacity = po.value;
        self.v_opacity = po.velocity;

        return !(px.settled and py.settled and pw.settled and ph.settled and po.settled);
    }
};

pub const MapAnimation = WindowAnimation;

/// Helper for compositor frame timing.
pub fn nowUs() TimeUs {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    return @as(TimeUs, @intCast(ts.sec)) * 1_000_000 + @as(TimeUs, @intCast(ts.nsec)) / 1000;
}

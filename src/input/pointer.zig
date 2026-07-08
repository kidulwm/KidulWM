const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const Server = @import("../server.zig").Server;
const Window = @import("../window.zig").Window;

pub const PointerManager = struct {
    server: *Server,

    motion: wl.Listener(*wlr.Pointer.event.Motion),
    motion_absolute: wl.Listener(*wlr.Pointer.event.MotionAbsolute),
    button: wl.Listener(*wlr.Pointer.event.Button),
    axis: wl.Listener(*wlr.Pointer.event.Axis),
    frame: wl.Listener(*wlr.Pointer),

    pub fn init(server: *Server) PointerManager {
        var self = PointerManager{
            .server = server,
            .motion = wl.Listener(*wlr.Pointer.event.Motion).init(handleMotion),
            .motion_absolute = wl.Listener(*wlr.Pointer.event.MotionAbsolute).init(handleMotionAbsolute),
            .button = wl.Listener(*wlr.Pointer.event.Button).init(handleButton),
            .axis = wl.Listener(*wlr.Pointer.event.Axis).init(handleAxis),
            .frame = wl.Listener(*wlr.Pointer).init(handleFrame),
        };
        self.motion.link.init();
        self.motion_absolute.link.init();
        self.button.link.init();
        self.axis.link.init();
        self.frame.link.init();
        return self;
    }

    pub fn listen(self: *PointerManager, pointer: *wlr.Pointer) void {
        pointer.events.motion.add(&self.motion);
        pointer.events.motion_absolute.add(&self.motion_absolute);
        pointer.events.button.add(&self.button);
        pointer.events.axis.add(&self.axis);
        pointer.events.frame.add(&self.frame);
    }

    fn timeMsec() u32 {
        var ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
        return @intCast(@mod(@as(i64, ts.sec) * 1000 + @divFloor(ts.nsec, std.time.ns_per_ms), std.math.maxInt(u32)));
    }

    fn handleMotion(listener: *wl.Listener(*wlr.Pointer.event.Motion), event: *wlr.Pointer.event.Motion) void {
        const self: *PointerManager = @fieldParentPtr("motion", listener);
        self.server.cursor_x += event.delta_x;
        self.server.cursor_y += event.delta_y;
        self.server.cursor.move(event.delta_x, event.delta_y);
        self.server.seat.pointerNotifyMotion(timeMsec(), self.server.cursor_x, self.server.cursor_y);
    }

    fn handleMotionAbsolute(listener: *wl.Listener(*wlr.Pointer.event.MotionAbsolute), event: *wlr.Pointer.event.MotionAbsolute) void {
        const self: *PointerManager = @fieldParentPtr("motion_absolute", listener);
        self.server.cursor_x = event.x;
        self.server.cursor_y = event.y;
        self.server.cursor.warpAbsolute(null, event.x, event.y);
        self.server.seat.pointerNotifyMotion(event.time_msec, self.server.cursor_x, self.server.cursor_y);
    }

    fn handleButton(listener: *wl.Listener(*wlr.Pointer.event.Button), event: *wlr.Pointer.event.Button) void {
        const self: *PointerManager = @fieldParentPtr("button", listener);
        _ = self.server.seat.pointerNotifyButton(event.time_msec, event.button, event.state);
        if (event.state == .pressed) {
            self.server.focusAtCursor();
        }
    }

    fn handleAxis(listener: *wl.Listener(*wlr.Pointer.event.Axis), event: *wlr.Pointer.event.Axis) void {
        const self: *PointerManager = @fieldParentPtr("axis", listener);
        self.server.seat.pointerNotifyAxis(
            event.time_msec,
            event.orientation,
            event.delta,
            event.delta_discrete,
            event.source,
            event.relative_direction,
        );
    }

    fn handleFrame(listener: *wl.Listener(*wlr.Pointer), pointer: *wlr.Pointer) void {
        _ = pointer;
        const self: *PointerManager = @fieldParentPtr("frame", listener);
        self.server.seat.pointerNotifyFrame();
    }
};

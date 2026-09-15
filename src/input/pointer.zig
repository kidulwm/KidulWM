const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const Server = @import("../server.zig").Server;

const PointerDevice = struct {
    manager: *PointerManager,
    pointer: *wlr.Pointer,
    input_device: *wlr.InputDevice,
    link: wl.list.Link,

    motion: wl.Listener(*wlr.Pointer.event.Motion),
    motion_absolute: wl.Listener(*wlr.Pointer.event.MotionAbsolute),
    button: wl.Listener(*wlr.Pointer.event.Button),
    axis: wl.Listener(*wlr.Pointer.event.Axis),
    frame: wl.Listener(*wlr.Pointer),
    device_destroy: wl.Listener(*wlr.InputDevice),

    fn create(
        manager: *PointerManager,
        pointer: *wlr.Pointer,
        input_device: *wlr.InputDevice,
        allocator: std.mem.Allocator,
    ) !*PointerDevice {
        const device = try allocator.create(PointerDevice);
        device.* = .{
            .manager = manager,
            .pointer = pointer,
            .input_device = input_device,
            .link = undefined,
            .motion = wl.Listener(*wlr.Pointer.event.Motion).init(handleMotion),
            .motion_absolute = wl.Listener(*wlr.Pointer.event.MotionAbsolute).init(handleMotionAbsolute),
            .button = wl.Listener(*wlr.Pointer.event.Button).init(handleButton),
            .axis = wl.Listener(*wlr.Pointer.event.Axis).init(handleAxis),
            .frame = wl.Listener(*wlr.Pointer).init(handleFrame),
            .device_destroy = wl.Listener(*wlr.InputDevice).init(handleDestroy),
        };
        device.motion.link.init();
        device.motion_absolute.link.init();
        device.button.link.init();
        device.axis.link.init();
        device.frame.link.init();
        device.device_destroy.link.init();
        device.link.init();

        pointer.events.motion.add(&device.motion);
        pointer.events.motion_absolute.add(&device.motion_absolute);
        pointer.events.button.add(&device.button);
        pointer.events.axis.add(&device.axis);
        pointer.events.frame.add(&device.frame);
        input_device.events.destroy.add(&device.device_destroy);

        manager.devices.append(device);
        return device;
    }

    fn destroy(self: *PointerDevice) void {
        // wlr_pointer_finish (0.20) ASSERTS all its event listener lists are
        // empty — it does NOT clean them. Detach every listener we
        // registered or hot-unplugging a pointer aborts the compositor
        // (SIGABRT), exactly like the keyboard case.
        self.motion.link.remove();
        self.motion_absolute.link.remove();
        self.button.link.remove();
        self.axis.link.remove();
        self.frame.link.remove();
        self.device_destroy.link.remove();
        self.link.remove();
        self.manager.server.cursor.detachInputDevice(self.input_device);
        self.manager.server.input_device_counts.pointer -|= 1;
        self.manager.server.allocator.destroy(self);
    }

    fn handleDestroy(listener: *wl.Listener(*wlr.InputDevice), input_device: *wlr.InputDevice) void {
        const self: *PointerDevice = @fieldParentPtr("device_destroy", listener);
        _ = input_device;
        self.destroy();
    }

    fn handleMotion(listener: *wl.Listener(*wlr.Pointer.event.Motion), event: *wlr.Pointer.event.Motion) void {
        const self: *PointerDevice = @fieldParentPtr("motion", listener);
        const server = self.manager.server;
        server.cursor.move(null, event.delta_x, event.delta_y);
        // SINGLE CURSOR TRUTH (2026-09-15): never accumulate deltas into a
        // parallel cursor_x/cursor_y — wlroots clamps the real cursor to the
        // output layout, the parallel copies didn't, and after any warp the
        // two diverged permanently (negative coords → node.at() always missed
        // → zero pointer enters → dead clicks/scroll/hover system-wide while
        // keyboard kept working). Read the clamped truth back from wlroots.
        server.cursor_x = server.cursor.x;
        server.cursor_y = server.cursor.y;
        if (server.handlePointerMove(server.cursor_x, server.cursor_y)) {
            server.logPointerDiagnostic("motion", server.cursor_x, server.cursor_y);
            return;
        }
        // PTR-PASS probe (rate-limited in logPointerDiagnostic): motion was
        // NOT claimed by spyglass/tray — it goes to the seat/surface here.
        server.logPointerDiagnostic("pass", server.cursor_x, server.cursor_y);
        server.pointerEnterAtCursor();
        server.seat.pointerNotifyMotion(timeMsec(), server.cursor_x, server.cursor_y);
        server.focusFollowsCursor();
    }

    fn handleMotionAbsolute(listener: *wl.Listener(*wlr.Pointer.event.MotionAbsolute), event: *wlr.Pointer.event.MotionAbsolute) void {
        const self: *PointerDevice = @fieldParentPtr("motion_absolute", listener);
        const server = self.manager.server;
        var box: wlr.Box = undefined;
        server.output_layout.getBox(null, &box);
        server.cursor.warpAbsolute(null, event.x * @as(f64, @floatFromInt(box.width)), event.y * @as(f64, @floatFromInt(box.height)));
        // Same law as handleMotion: wlroots owns the position, we mirror it.
        server.cursor_x = server.cursor.x;
        server.cursor_y = server.cursor.y;
        if (server.handlePointerMove(server.cursor_x, server.cursor_y)) {
            server.logPointerDiagnostic("abs", server.cursor_x, server.cursor_y);
            return;
        }
        server.pointerEnterAtCursor();
        server.seat.pointerNotifyMotion(event.time_msec, server.cursor_x, server.cursor_y);
        server.focusFollowsCursor();
    }

    fn handleButton(listener: *wl.Listener(*wlr.Pointer.event.Button), event: *wlr.Pointer.event.Button) void {
        const self: *PointerDevice = @fieldParentPtr("button", listener);
        const server = self.manager.server;
        if (event.state == .pressed) {
            if (server.handlePointerClick(server.cursor_x, server.cursor_y)) {
                server.logPointerDiagnostic("click", server.cursor_x, server.cursor_y);
                return;
            }
        }
        // Belt-and-braces: a click can land without any prior motion event
        // (e.g. touch or a fresh seat), so ensure the surface is entered.
        server.pointerEnterAtCursor();
        const result = server.seat.pointerNotifyButton(event.time_msec, event.button, event.state);
        std.log.info("KidulWM: BTN-NOTIFY btn=0x{x} state={s} serial={d} focused={}", .{ event.button, @tagName(event.state), result, server.seat.pointer_state.focused_surface != null });
        if (event.state == .pressed) {
            server.focusAtCursor();
        }
    }

    fn handleAxis(listener: *wl.Listener(*wlr.Pointer.event.Axis), event: *wlr.Pointer.event.Axis) void {
        const self: *PointerDevice = @fieldParentPtr("axis", listener);
        const server = self.manager.server;
        if (server.handlePointerAxis(server.cursor_x, server.cursor_y, event.delta)) {
            return;
        }
        server.seat.pointerNotifyAxis(
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
        const self: *PointerDevice = @fieldParentPtr("frame", listener);
        self.manager.server.seat.pointerNotifyFrame();
    }

    fn timeMsec() u32 {
        var ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
        return @intCast(@mod(@as(i64, ts.sec) * 1000 + @divFloor(ts.nsec, std.time.ns_per_ms), std.math.maxInt(u32)));
    }
};

pub const PointerManager = struct {
    server: *Server,
    devices: wl.list.Head(PointerDevice, .link),

    pub fn init(self: *PointerManager, server: *Server) void {
        self.* = .{
            .server = server,
            .devices = undefined,
        };
        self.devices.init();
    }

    pub fn listen(self: *PointerManager, pointer: *wlr.Pointer, input_device: *wlr.InputDevice) void {
        _ = PointerDevice.create(self, pointer, input_device, self.server.allocator) catch |err| {
            std.log.err("failed to allocate pointer device state: {}", .{err});
        };
    }

    pub fn deinit(self: *PointerManager) void {
        while (self.devices.first()) |device| {
            device.destroy();
        }
    }
};

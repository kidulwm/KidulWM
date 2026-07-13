const std = @import("std");
const linux = std.os.linux;
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");
const Server = @import("../server.zig").Server;

const KeyboardDevice = struct {
    manager: *KeyboardManager,
    keyboard: *wlr.Keyboard,
    input_device: *wlr.InputDevice,
    link: wl.list.Link,

    key: wl.Listener(*wlr.Keyboard.event.Key),
    modifiers: wl.Listener(*wlr.Keyboard),
    device_destroy: wl.Listener(*wlr.InputDevice),

    fn create(
        manager: *KeyboardManager,
        keyboard: *wlr.Keyboard,
        input_device: *wlr.InputDevice,
        allocator: std.mem.Allocator,
    ) !*KeyboardDevice {
        const device = try allocator.create(KeyboardDevice);
        device.* = .{
            .manager = manager,
            .keyboard = keyboard,
            .input_device = input_device,
            .link = undefined,
            .key = wl.Listener(*wlr.Keyboard.event.Key).init(handleKey),
            .modifiers = wl.Listener(*wlr.Keyboard).init(handleModifiers),
            .device_destroy = wl.Listener(*wlr.InputDevice).init(handleDestroy),
        };
        device.key.link.init();
        device.modifiers.link.init();
        device.device_destroy.link.init();
        device.link.init();

        keyboard.events.key.add(&device.key);
        keyboard.events.modifiers.add(&device.modifiers);
        input_device.events.destroy.add(&device.device_destroy);

        manager.devices.append(device);
        return device;
    }

    fn destroy(self: *KeyboardDevice) void {
        // The input device and its signals are being destroyed; wlroots cleans
        // its own signal lists, so only detach from the manager list here.
        self.link.remove();
        self.manager.server.input_device_counts.keyboard -|= 1;
        self.manager.server.allocator.destroy(self);
    }

    fn handleDestroy(listener: *wl.Listener(*wlr.InputDevice), input_device: *wlr.InputDevice) void {
        const self: *KeyboardDevice = @fieldParentPtr("device_destroy", listener);
        _ = input_device;
        self.destroy();
    }

    fn handleKey(listener: *wl.Listener(*wlr.Keyboard.event.Key), event: *wlr.Keyboard.event.Key) void {
        const self: *KeyboardDevice = @fieldParentPtr("key", listener);
        const server = self.manager.server;
        if (event.state != .pressed) {
            server.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
            return;
        }
        const keyboard = server.seat.getKeyboard() orelse {
            server.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
            return;
        };
        const state = keyboard.xkb_state orelse {
            server.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
            return;
        };
        const sym = xkb.State.keyGetOneSym(state, event.keycode + 8);
        const mod4_active = xkb.State.modNameIsActive(
            state,
            "Mod4",
            @as(xkb.State.Component, @enumFromInt(xkb.State.Component.mods_depressed)),
        ) > 0;
        if (mod4_active and sym == xkb.Keysym.Return) {
            spawnTerminal();
            return;
        }
        if (mod4_active and sym == xkb.Keysym.j) {
            server.focusNext();
            return;
        }
        if (mod4_active and sym == xkb.Keysym.k) {
            server.focusPrev();
            return;
        }
        if (mod4_active and sym == xkb.Keysym.t) {
            server.tray.toggle();
            return;
        }
        if (mod4_active and sym == xkb.Keysym.a) {
            server.nextAnimationKind();
            return;
        }
        server.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
    }

    fn handleModifiers(listener: *wl.Listener(*wlr.Keyboard), keyboard: *wlr.Keyboard) void {
        const self: *KeyboardDevice = @fieldParentPtr("modifiers", listener);
        self.manager.server.seat.keyboardNotifyModifiers(&keyboard.modifiers);
    }

    fn spawnTerminal() void {
        const pid = linux.fork();
        if (@as(isize, @bitCast(pid)) < 0) {
            std.log.warn("KidulWM: fork failed", .{});
            return;
        }
        if (pid != 0) return; // parent

        const devnull = linux.open("/dev/null", .{ .ACCMODE = .RDONLY }, 0);
        if (@as(isize, @bitCast(devnull)) < 0) {
            std.log.warn("KidulWM: failed to open /dev/null", .{});
            linux.exit(127);
        }
        const fd: i32 = @intCast(devnull);
        _ = linux.dup2(fd, linux.STDIN_FILENO);
        _ = linux.dup2(fd, linux.STDOUT_FILENO);
        _ = linux.dup2(fd, linux.STDERR_FILENO);
        _ = linux.close(fd);

        const argv = [_:null]?[*:0]const u8{"/usr/bin/ghostty"};
        const envp = [_:null]?[*:0]const u8{
            "WAYLAND_DISPLAY=wayland-1",
            "XDG_RUNTIME_DIR=/run/user/1000",
            "GHOSTTY_RESOURCES_DIR=/usr/share/ghostty",
        };
        _ = linux.execve("/usr/bin/ghostty", &argv, &envp);
        linux.exit(127);
    }
};

pub const KeyboardManager = struct {
    server: *Server,
    devices: wl.list.Head(KeyboardDevice, .link),

    pub fn init(self: *KeyboardManager, server: *Server) void {
        self.* = .{
            .server = server,
            .devices = undefined,
        };
        self.devices.init();
    }

    pub fn listen(self: *KeyboardManager, keyboard: *wlr.Keyboard, input_device: *wlr.InputDevice) void {
        _ = KeyboardDevice.create(self, keyboard, input_device, self.server.allocator) catch |err| {
            std.log.err("failed to allocate keyboard device state: {}", .{err});
        };
    }

    pub fn deinit(self: *KeyboardManager) void {
        while (self.devices.first()) |device| {
            device.destroy();
        }
    }
};

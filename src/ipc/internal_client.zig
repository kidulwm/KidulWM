//! Internal Wayland client (CARD 2b slice 1): the compositor's own
//! slide-host surfaces ride this. socketpair → wl_client_create (server
//! side) → wl_display_connect_to_fd (client side) → registry sync →
//! wl_compositor + xdg_wm_base + zxdg_exporter_v2. One host xdg_toplevel
//! per .video slide; the surface never paints — it exists to be exported
//! (handle sent to kplayd) and to carry the video rect for the compositor's
//! placement pass.
//!
//! DEADLOCK LAW: this client talks to its OWN server on the SAME thread.
//! A stock wl_display_roundtrip() blocks in poll() waiting for the server
//! — which can never dispatch, because the thread is inside roundtrip.
//! All synchronization goes through pumpRoundtrip(): flush → dispatch the
//! SERVER loop (timeout 0) → flush server clients → dispatch pending
//! client events, until the sync callback lands.
// SPDX-License-Identifier: GPL-3.0-or-later

const std = @import("std");
const wayland = @import("wayland");

const client = wayland.client;
const server_wl = wayland.server.wl;

const ffi_client = struct {
    pub extern fn wl_display_flush(display: *client.wl.Display) c_int;
    pub extern fn wl_display_dispatch_pending(display: *client.wl.Display) c_int;
    pub extern fn wl_display_prepare_read(display: *client.wl.Display) c_int;
    pub extern fn wl_display_read_events(display: *client.wl.Display) c_int;
    pub extern fn wl_display_cancel_read(display: *client.wl.Display) void;
    /// libwayland-server does NOT auto-flush: server-queued events (registry
    /// globals, sync dones, export handles) sit in the client's out-buffer
    /// until the compositor calls this. wl_display_run() does it per loop
    /// iteration — our pump must do it too (this is what wl_server.run()
    /// would do once started).
    pub extern fn wl_display_flush_clients(display: *server_wl.Server) void;
};

const c = @cImport({
    @cInclude("sys/socket.h");
    @cInclude("unistd.h");
});

pub const Error = error{
    SocketpairFailed,
    ClientCreateFailed,
    ConnectFailed,
    RegistryBindFailed,
    PumpFailed,
    ExportFailed,
    OutOfMemory,
};

/// Pump the client↔server circuit until `done` flips true. `done` is set
/// by a wl_callback (display.sync) listener. Returns error.PumpFailed if
/// the circuit makes no progress for `max_idle` consecutive iterations.
fn pumpRoundtrip(ic: *InternalClient, done: *bool) Error!void {
    var idle: u32 = 0;
    const max_idle: u32 = 10_000; // generous; each spin is µs-scale
    while (!done.*) {
        const flushed = ffi_client.wl_display_flush(ic.display);
        _ = flushed;
        // Dispatch the server loop with a small timeout: timeout=0 only
        // processes already-queued events; the socketpair fd needs the
        // loop's poll to fire. 1ms keeps it snappy without busy-spin.
        ic.event_loop.dispatch(1) catch return error.PumpFailed;
        ic.event_loop.dispatchIdle(); // fires sync callbacks queued by the server
        // Push server-queued events back over the socket (wl_display_run
        // does this every iteration; we are not inside run() yet).
        ffi_client.wl_display_flush_clients(ic.wl_display);
        _ = ffi_client.wl_display_flush(ic.display);
        // Client-side read: dispatch_pending only handles events already
        // pulled off the socket. prepare_read + read_events pulls them.
        if (ffi_client.wl_display_prepare_read(ic.display) == 0) {
            _ = ffi_client.wl_display_read_events(ic.display);
        } else {
            ffi_client.wl_display_cancel_read(ic.display);
        }
        const dispatched = ffi_client.wl_display_dispatch_pending(ic.display);
        _ = dispatched;
        idle += 1;
        if (idle > max_idle) {
            std.log.err("KidulWM: internal-client pump stalled (no progress after {d} iterations)", .{idle});
            return error.PumpFailed;
        }
    }
}

fn syncListener(_: *client.wl.Callback, event: client.wl.Callback.Event, done: *bool) void {
    switch (event) {
        .done => done.* = true,
    }
}

pub const InternalClient = struct {
    allocator: std.mem.Allocator,
    /// Server-side handle (compositor keeps this; destroys on shutdown).
    server_client: *server_wl.Client,
    /// Client-side display connection over the socketpair.
    display: *client.wl.Display,
    /// The compositor's own event loop — pumped during sync roundtrips.
    event_loop: *server_wl.EventLoop,
    /// The raw wl_display for flush_clients in the pump.
    wl_display: *server_wl.Server,
    registry: *client.wl.Registry,

    compositor: ?*client.wl.Compositor = null,
    xdg_wm_base: ?*client.xdg.WmBase = null,
    exporter: ?*client.zxdg.ExporterV2 = null,

    pub fn create(allocator: std.mem.Allocator, wl_srv: *server_wl.Server) Error!*InternalClient {
        var fds: [2]c_int = undefined;
        if (c.socketpair(c.AF_UNIX, c.SOCK_STREAM | c.SOCK_CLOEXEC, 0, &fds) != 0)
            return error.SocketpairFailed;

        // Server end: wl_client_create takes ownership of fds[0].
        const server_client = server_wl.Client.create(wl_srv, fds[0]) orelse {
            _ = c.close(fds[0]);
            _ = c.close(fds[1]);
            return error.ClientCreateFailed;
        };

        // Client end: wl_display_connect_to_fd takes ownership of fds[1].
        const display = client.wl.Display.connectToFd(fds[1]) catch {
            _ = c.close(fds[1]);
            server_client.destroy();
            return error.ConnectFailed;
        };

        const self = allocator.create(InternalClient) catch {
            display.disconnect();
            server_client.destroy();
            return error.OutOfMemory;
        };
        self.* = .{
            .allocator = allocator,
            .server_client = server_client,
            .display = display,
            .event_loop = wl_srv.getEventLoop(),
            .wl_display = wl_srv,
            .registry = undefined,
        };

        self.registry = display.getRegistry() catch {
            self.destroy();
            return error.RegistryBindFailed;
        };
        self.registry.setListener(*InternalClient, registryListener, self);
        // Pump 1 collects globals, pump 2 confirms the binds.
        try self.sync();
        try self.sync();

        if (self.compositor == null or self.xdg_wm_base == null or self.exporter == null) {
            self.destroy();
            return error.RegistryBindFailed;
        }
        std.log.info("KidulWM: internal client up (compositor + xdg_wm_base + zxdg_exporter_v2 bound)", .{});
        return self;
    }

    /// Barrier: every outstanding request has been processed by the server
    /// and its resulting events delivered back to us. Single-thread safe.
    pub fn sync(self: *InternalClient) Error!void {
        var done = false;
        const cb = self.display.sync() catch return error.PumpFailed;
        cb.setListener(*bool, syncListener, &done);
        try pumpRoundtrip(self, &done);
        cb.destroy();
    }

    pub fn destroy(self: *InternalClient) void {
        if (self.exporter) |e| e.destroy();
        if (self.xdg_wm_base) |w| w.destroy();
        if (self.compositor) |cm| cm.destroy();
        self.registry.destroy();
        self.display.disconnect();
        self.server_client.destroy();
        self.allocator.destroy(self);
    }

    fn registryListener(_: *client.wl.Registry, event: client.wl.Registry.Event, self: *InternalClient) void {
        switch (event) {
            .global => |g| {
                if (std.mem.orderZ(u8, g.interface, "wl_compositor") == .eq) {
                    self.compositor = self.registry.bind(g.name, client.wl.Compositor, @min(g.version, 4)) catch null;
                } else if (std.mem.orderZ(u8, g.interface, "xdg_wm_base") == .eq) {
                    self.xdg_wm_base = self.registry.bind(g.name, client.xdg.WmBase, @min(g.version, 2)) catch null;
                } else if (std.mem.orderZ(u8, g.interface, "zxdg_exporter_v2") == .eq) {
                    self.exporter = self.registry.bind(g.name, client.zxdg.ExporterV2, @min(g.version, 1)) catch null;
                }
            },
            .global_remove => {},
        }
    }
};

/// One host xdg_toplevel per .video slide. Never paints; exists to be
/// exported (zxdg_exporter_v2 → handle sent to kplayd over kplay.sock) and
/// to carry the video rect for the compositor's placement pass.
pub const HostSurface = struct {
    allocator: std.mem.Allocator,
    surface: *client.wl.Surface,
    xdg_surface: *client.xdg.Surface,
    toplevel: *client.xdg.Toplevel,
    exported: *client.zxdg.ExportedV2,

    /// Owned copy of the export handle (the token kplayd imports).
    handle: ?[]u8 = null,

    pub fn create(ic: *InternalClient, app_id: [*:0]const u8, title: [*:0]const u8) Error!*HostSurface {
        const surface = ic.compositor.?.createSurface() catch return error.ExportFailed;
        const xdg_surface = ic.xdg_wm_base.?.getXdgSurface(surface) catch return error.ExportFailed;
        const toplevel = xdg_surface.getToplevel() catch return error.ExportFailed;
        toplevel.setAppId(app_id);
        toplevel.setTitle(title);
        // Initial empty commit so the toplevel exists compositor-side
        // before we export it.
        surface.commit();

        const exported = ic.exporter.?.exportToplevel(surface) catch return error.ExportFailed;

        const self = ic.allocator.create(HostSurface) catch return error.OutOfMemory;
        self.* = .{
            .allocator = ic.allocator,
            .surface = surface,
            .xdg_surface = xdg_surface,
            .toplevel = toplevel,
            .exported = exported,
        };
        exported.setListener(*HostSurface, exportedListener, self);

        // Pump: compositor processes the commit + export and sends the
        // handle event back.
        try ic.sync();
        if (self.handle == null) {
            self.destroy();
            return error.ExportFailed;
        }
        return self;
    }

    pub fn destroy(self: *HostSurface) void {
        if (self.handle) |h| self.allocator.free(h);
        self.exported.destroy();
        self.toplevel.destroy();
        self.xdg_surface.destroy();
        self.surface.destroy();
        self.allocator.destroy(self);
    }

    fn exportedListener(_: *client.zxdg.ExportedV2, event: client.zxdg.ExportedV2.Event, self: *HostSurface) void {
        switch (event) {
            .handle => |h| {
                if (self.handle == null) {
                    self.handle = self.allocator.dupe(u8, std.mem.span(h.handle)) catch null;
                }
            },
        }
    }
};

const std = @import("std");
const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = Scanner.create(b, .{});

    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("unstable/xdg-decoration/xdg-decoration-unstable-v1.xml");
    scanner.addSystemProtocol("staging/ext-session-lock/ext-session-lock-v1.xml");
    scanner.addSystemProtocol("staging/cursor-shape/cursor-shape-v1.xml");
    scanner.addSystemProtocol("staging/tearing-control/tearing-control-v1.xml");
    scanner.addSystemProtocol("staging/color-management/color-management-v1.xml");
    scanner.addSystemProtocol("staging/color-representation/color-representation-v1.xml");

    scanner.addCustomProtocol(b.path("protocol/wlr-layer-shell-unstable-v1.xml"));
    scanner.addCustomProtocol(b.path("protocol/wlr-output-power-management-unstable-v1.xml"));
    scanner.addCustomProtocol(b.path("protocol/kidul-settings-tray-v1.xml"));

    scanner.generate("wl_compositor", 4);
    scanner.generate("wl_subcompositor", 1);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 7);
    scanner.generate("wl_data_device_manager", 3);

    scanner.generate("xdg_wm_base", 2);
    scanner.generate("zxdg_decoration_manager_v1", 1);
    scanner.generate("ext_session_lock_manager_v1", 1);
    scanner.generate("wp_cursor_shape_manager_v1", 1);
    scanner.generate("wp_tearing_control_manager_v1", 1);
    scanner.generate("wp_color_manager_v1", 1);
    scanner.generate("wp_color_representation_manager_v1", 1);

    scanner.generate("zwlr_layer_shell_v1", 5);
    scanner.generate("zwlr_output_power_manager_v1", 1);
    scanner.generate("kidul_settings_tray_v1", 1);

    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    const xkbcommon = b.dependency("xkbcommon", .{}).module("xkbcommon");
    const pixman = b.dependency("pixman", .{}).module("pixman");
    const toml = b.dependency("toml", .{}).module("toml");

    const wlroots = b.dependency("wlroots", .{}).module("wlroots");
    wlroots.addImport("wayland", wayland);
    wlroots.addImport("xkbcommon", xkbcommon);
    wlroots.addImport("pixman", pixman);
    wlroots.resolved_target = target;
    wlroots.linkSystemLibrary("wlroots-0.20", .{});

    const weather_mod = b.createModule(.{
        .root_source_file = b.path("src/ui/weather.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    weather_mod.addImport("wayland", wayland);
    weather_mod.addImport("wlroots", wlroots);
    weather_mod.addImport("core", b.createModule(.{ .root_source_file = b.path("src/core/style.zig") }));

    const moon_mod = b.createModule(.{
        .root_source_file = b.path("src/util/moon.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    moon_mod.addImport("dm", b.createModule(.{ .root_source_file = b.path("src/dm/c.zig") }));

    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    root_mod.addImport("wayland", wayland);
    root_mod.addImport("wlroots", wlroots);
    root_mod.addImport("xkbcommon", xkbcommon);
    root_mod.addImport("pixman", pixman);
    root_mod.addImport("toml", toml);
    root_mod.addImport("weather", weather_mod);
    root_mod.addImport("moon", moon_mod);

    root_mod.linkSystemLibrary("wayland-server", .{});
    root_mod.linkSystemLibrary("wlroots-0.20", .{});
    root_mod.linkSystemLibrary("xkbcommon", .{});
    root_mod.linkSystemLibrary("pixman-1", .{});
    root_mod.linkSystemLibrary("libinput", .{});
    root_mod.linkSystemLibrary("cairo", .{});

    const dm_mod = b.createModule(.{
        .root_source_file = b.path("src/dm/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dm_mod.linkSystemLibrary("cairo", .{});
    dm_mod.linkSystemLibrary("png16", .{});
    dm_mod.linkSystemLibrary("drm", .{});
    dm_mod.linkSystemLibrary("seat", .{});

    const dm_exe = b.addExecutable(.{ .name = "kiduldm", .root_module = dm_mod });
    b.installArtifact(dm_exe);

    const exe = b.addExecutable(.{ .name = "kidulwm", .root_module = root_mod });
    b.installArtifact(exe);

    const control_mod = b.createModule(.{
        .root_source_file = b.path("src/kidulwm-control.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    control_mod.addImport("ipc", b.createModule(.{ .root_source_file = b.path("src/ipc.zig") }));
    const control_exe = b.addExecutable(.{ .name = "kidulwm-control", .root_module = control_mod });
    b.installArtifact(control_exe);

    b.installFile("config/keybinds.conf", "share/kidulwm/keybinds.conf");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run KidulWM");
    run_step.dependOn(&run_cmd.step);

    const layout_tests = b.addTest(.{
        .name = "layout-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/core/layout.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const test_step = b.step("test", "Run layout tests");
    test_step.dependOn(&layout_tests.step);
}

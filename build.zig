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
    root_mod.addImport("dm", b.createModule(.{ .root_source_file = b.path("src/dm/c.zig") }));

    root_mod.linkSystemLibrary("wayland-server", .{});
    root_mod.linkSystemLibrary("wlroots-0.20", .{});
    root_mod.linkSystemLibrary("xkbcommon", .{});
    root_mod.linkSystemLibrary("pixman-1", .{});
    root_mod.linkSystemLibrary("libinput", .{});
    root_mod.linkSystemLibrary("cairo", .{});
    root_mod.linkSystemLibrary("pipewire-0.3", .{});
    root_mod.addCSourceFile(.{
        .file = b.path("src/core/kmedia_shim.c"),
        .flags = &.{
            "-I/usr/include/pipewire-0.3",
            "-I/usr/include/spa-0.2",
            "-D_REENTRANT",
        },
    });

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

    // TODO: replace python bridge with native Zig D-Bus service.
    // The Zig bridge scaffold lives in src/notify-bridge/ but is not yet
    // compiling; leaving it out of the build keeps `zig build` green while
    // notifications flow through the Python bridge installed as a systemd
    // user service (config/systemd/user/kidulwm-notify-bridge.service).

    const moon_test_mod = b.createModule(.{
        .root_source_file = b.path("src/test_moon.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    moon_test_mod.addImport("moon", moon_mod);
    moon_test_mod.linkSystemLibrary("cairo", .{});
    const moon_test_exe = b.addExecutable(.{ .name = "moon-test", .root_module = moon_test_mod });
    const moon_test_run = b.addRunArtifact(moon_test_exe);
    moon_test_run.step.dependOn(b.getInstallStep());
    const moon_test_step = b.step("moon-test", "Render moon test strip to /tmp/moon_test.png");
    moon_test_step.dependOn(&moon_test_run.step);

    const gauge_test_mod = b.createModule(.{
        .root_source_file = b.path("src/test_gauge.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    gauge_test_mod.addImport("dm", b.createModule(.{ .root_source_file = b.path("src/dm/c.zig") }));
    gauge_test_mod.addImport("core", b.createModule(.{ .root_source_file = b.path("src/core/style.zig") }));
    gauge_test_mod.linkSystemLibrary("cairo", .{});
    const gauge_test_exe = b.addExecutable(.{ .name = "gauge-test", .root_module = gauge_test_mod });
    const gauge_test_run = b.addRunArtifact(gauge_test_exe);
    gauge_test_run.step.dependOn(b.getInstallStep());
    const gauge_test_step = b.step("gauge-test", "Render gauge test strip to /tmp/gauge_test.png");
    gauge_test_step.dependOn(&gauge_test_run.step);

    b.installFile("config/keybinds.conf", "share/kidulwm/keybinds.conf");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run KidulWM");
    run_step.dependOn(&run_cmd.step);

    const files_mod = b.createModule(.{
        .root_source_file = b.path("tools/kidul-files/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const files_exe = b.addExecutable(.{ .name = "kidul-files", .root_module = files_mod });
    b.installArtifact(files_exe);

    const kmedia_test_mod = b.createModule(.{
        .root_source_file = b.path("src/test_kmedia.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    kmedia_test_mod.linkSystemLibrary("pipewire-0.3", .{});
    kmedia_test_mod.addCSourceFile(.{
        .file = b.path("src/core/kmedia_shim.c"),
        .flags = &.{
            "-I/usr/include/pipewire-0.3",
            "-I/usr/include/spa-0.2",
            "-D_REENTRANT",
        },
    });
    const kmedia_test_exe = b.addExecutable(.{ .name = "kmedia-test", .root_module = kmedia_test_mod });
    b.installArtifact(kmedia_test_exe);

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

const std = @import("std");
const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── compile-time provenance stamps ─────────────────────────────────
    // KidulWM statically includes kmedia as source modules (../kmedia/src)
    // — a kmedia change is INVISIBLE at runtime until KidulWM is rebuilt
    // and redeployed. Stamp both HEADs into the binary so session.log can
    // always prove which player code is actually running (2026-09-09: the
    // census hunt lost a morning to "deployed" probes that weren't).
    const kidulwm_rev = b.run(&.{ "git", "-C", b.pathFromRoot("."), "rev-parse", "--short", "HEAD" });
    const kmedia_rev = b.run(&.{ "git", "-C", b.pathFromRoot("../kmedia"), "rev-parse", "--short", "HEAD" });
    const stamp = b.addOptions();
    stamp.addOption([]const u8, "kidulwm_rev", std.mem.trim(u8, kidulwm_rev, " \n\r"));
    stamp.addOption([]const u8, "kmedia_rev", std.mem.trim(u8, kmedia_rev, " \n\r"));

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
    // xdg-foreign v2 (CARD 2b): the internal client exports the video
    // slide's host surface; kplayd imports the handle.
    scanner.addCustomProtocol(b.path("protocol/xdg-foreign-unstable-v2.xml"));

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
    scanner.generate("zxdg_exporter_v2", 1);
    scanner.generate("zxdg_importer_v2", 1);

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

    // Weather + moon modules REMOVED 2026-09-17 (Barticus: "remove the
    // weather widget ASAP") — widget, painter, moon renderer and test
    // targets all deleted.

    // ── libkmedia dependency / module ──────────────────────────────────────
    const c_kmedia_mod = b.createModule(.{
        .root_source_file = b.path("../kmedia/src/c.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    c_kmedia_mod.linkSystemLibrary("cairo", .{});
    c_kmedia_mod.linkSystemLibrary("wayland-client", .{});
    c_kmedia_mod.linkSystemLibrary("wayland-cursor", .{});
    c_kmedia_mod.linkSystemLibrary("xkbcommon", .{});
    c_kmedia_mod.addSystemIncludePath(b.path("../kmedia/protocol"));

    const av_mod = b.createModule(.{
        .root_source_file = b.path("../kmedia/src/av.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    av_mod.linkSystemLibrary("avformat", .{});
    av_mod.linkSystemLibrary("avcodec", .{});
    av_mod.linkSystemLibrary("avutil", .{});
    av_mod.linkSystemLibrary("swscale", .{});
    av_mod.linkSystemLibrary("swresample", .{});
    av_mod.linkSystemLibrary("pulse", .{});
    av_mod.linkSystemLibrary("pulse-simple", .{});
    av_mod.linkSystemLibrary("pthread", .{});

    const libkmedia_mod = b.createModule(.{
        .root_source_file = b.path("../kmedia/src/libkmedia.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "c", .module = c_kmedia_mod },
            .{ .name = "av", .module = av_mod },
        },
    });
    libkmedia_mod.linkSystemLibrary("cairo", .{});
    libkmedia_mod.linkSystemLibrary("curl", .{});
    libkmedia_mod.linkSystemLibrary("avformat", .{});
    libkmedia_mod.linkSystemLibrary("avcodec", .{});
    libkmedia_mod.linkSystemLibrary("avutil", .{});
    libkmedia_mod.linkSystemLibrary("swscale", .{});
    libkmedia_mod.linkSystemLibrary("swresample", .{});
    libkmedia_mod.linkSystemLibrary("pulse", .{});
    libkmedia_mod.linkSystemLibrary("pulse-simple", .{});
    libkmedia_mod.linkSystemLibrary("pthread", .{});

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
    root_mod.addImport("kmedia", libkmedia_mod);
    root_mod.addOptions("build_stamp", stamp);
    root_mod.addImport("dm", b.createModule(.{ .root_source_file = b.path("src/dm/c.zig") }));

    root_mod.linkSystemLibrary("wayland-server", .{});
    root_mod.linkSystemLibrary("wlroots-0.20", .{});
    root_mod.linkSystemLibrary("xkbcommon", .{});
    root_mod.linkSystemLibrary("pixman-1", .{});
    root_mod.linkSystemLibrary("libinput", .{});
    root_mod.linkSystemLibrary("cairo", .{});
    root_mod.linkSystemLibrary("pipewire-0.3", .{});
    root_mod.linkSystemLibrary("avformat", .{});
    root_mod.linkSystemLibrary("avcodec", .{});
    root_mod.linkSystemLibrary("avutil", .{});
    root_mod.linkSystemLibrary("swscale", .{});
    root_mod.linkSystemLibrary("swresample", .{});
    root_mod.linkSystemLibrary("pulse", .{});
    root_mod.linkSystemLibrary("pulse-simple", .{});
    root_mod.linkSystemLibrary("pthread", .{});
    root_mod.linkSystemLibrary("va", .{});
    root_mod.addCSourceFile(.{
        .file = b.path("src/core/kmedia_shim.c"),
        .flags = &.{
            "-I/usr/include/pipewire-0.3",
            "-I/usr/include/spa-0.2",
            "-D_REENTRANT",
        },
    });
    root_mod.addCSourceFile(.{
        .file = b.path("src/core/kimg_shim.c"),
        .flags = &.{"-O2"},
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

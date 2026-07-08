const std = @import("std");
const wl = @import("wayland").server.wl;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const wayland = b.createModule(.{ .root_source_file = b.path(".zig-cache/o/9f466457ef426e9cfe23e8ec94173b03/wayland.zig") });
    const root_mod = b.createModule(.{
        .root_source_file = b.path("tmp_abi_check.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    root_mod.addImport("wayland", wayland);
    root_mod.linkSystemLibrary("wayland-server", .{});
    const exe = b.addExecutable(.{ .name = "abi-check", .root_module = root_mod });
    b.installArtifact(exe);
}

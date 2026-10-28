// SPDX-License-Identifier: GPL-3.0-or-later
const std = @import("std");

pub const Metric = enum {
    gpu_temp,
    cpu_temp,
    ram_usage,
    disk1_size,
    disk2_size,
};

pub const GaugeValue = struct {
    metric: Metric,
    label: []const u8,
    value: f64, // 0..1
    raw: f64,
    unit: []const u8,
};

pub const GaugeData = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GaugeData {
        return .{ .allocator = allocator };
    }

    pub fn sample(self: *const GaugeData, metric: Metric) !GaugeValue {
        _ = self;
        return switch (metric) {
            .gpu_temp => .{ .metric = metric, .label = "GPU", .value = (try readGpuTemp()) / 100.0, .raw = try readGpuTemp(), .unit = "°C" },
            .cpu_temp => .{ .metric = metric, .label = "CPU", .value = (try readCpuTemp()) / 100.0, .raw = try readCpuTemp(), .unit = "°C" },
            .ram_usage => blk: {
                const ram = try readRamUsage();
                break :blk .{ .metric = metric, .label = "RAM", .value = ram.used / ram.total, .raw = ram.used / ram.total * 100.0, .unit = "%" };
            },
            .disk1_size => blk: {
                const d = try readDiskUsage("/");
                break :blk .{ .metric = metric, .label = "D1", .value = d.used / d.total, .raw = d.used / d.total * 100.0, .unit = "%" };
            },
            .disk2_size => blk: {
                const d = try readDiskUsage("/home");
                break :blk .{ .metric = metric, .label = "D2", .value = d.used / d.total, .raw = d.used / d.total * 100.0, .unit = "%" };
            },
        };
    }
};

fn readCpuTemp() !f64 {
    const millideg = readFirstFloat("/sys/class/thermal/thermal_zone0/temp") catch return 45.0;
    return millideg / 1000.0;
}

fn readGpuTemp() !f64 {
    // TODO: proper GPU temp. Fallback to CPU for now.
    return readCpuTemp() catch 45.0;
}

const RamInfo = struct { used: f64, total: f64 };

fn readRamUsage() !RamInfo {
    const text = try readFileToBuf("/proc/meminfo");
    var total: f64 = 1;
    var available: f64 = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal:")) {
            total = parseFloatAfterColon(line) * 1024;
        } else if (std.mem.startsWith(u8, line, "MemAvailable:")) {
            available = parseFloatAfterColon(line) * 1024;
        }
    }
    return .{ .used = total - available, .total = total };
}

const DiskInfo = struct { used: f64, total: f64 };

fn readDiskUsage(path: []const u8) !DiskInfo {
    const c = @import("c");
    var buf: c.struct_statvfs = undefined;
    if (c.statvfs(path.ptr, &buf) != 0) return .{ .used = 0, .total = 1 };
    const total = @as(f64, @floatFromInt(buf.f_blocks)) * @as(f64, @floatFromInt(buf.f_frsize));
    const free = @as(f64, @floatFromInt(buf.f_bavail)) * @as(f64, @floatFromInt(buf.f_frsize));
    return .{ .used = total - free, .total = total };
}

fn readFirstFloat(path: []const u8) !f64 {
    const text = try readFileToBuf(path);
    return parseFloat(text);
}

fn readFileToBuf(path: []const u8) ![]const u8 {
    const linux = std.os.linux;
    var path_buf: [256:0]u8 = undefined;
    if (path.len >= path_buf.len) return error.PathTooLong;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;
    const fd = linux.open(&path_buf, .{ .ACCMODE = .RDONLY }, 0);
    if (@as(isize, @bitCast(fd)) < 0) return error.FileNotFound;
    const fd_i: i32 = @intCast(fd);
    defer _ = linux.close(fd_i);
    var buf: [4096]u8 = undefined;
    var end: usize = 0;
    while (true) {
        const n = linux.read(fd_i, &buf, buf.len);
        if (n < 0) return error.ReadFailed;
        if (n == 0) break;
        end = @as(usize, @intCast(n));
    }
    return buf[0..end];
}

fn parseFloatAfterColon(line: []const u8) f64 {
    var i: usize = 0;
    while (i < line.len and line[i] != ':') i += 1;
    i += 1;
    while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
    return parseFloat(line[i..]);
}

fn parseFloat(text: []const u8) f64 {
    var sum: f64 = 0;
    var div: f64 = 1;
    var in_frac = false;
    var sign: f64 = 1;
    var i: usize = 0;
    while (i < text.len and (text[i] == ' ' or text[i] == '\n' or text[i] == '\t')) i += 1;
    if (i < text.len and text[i] == '-') {
        sign = -1;
        i += 1;
    }
    while (i < text.len) : (i += 1) {
        const ch = text[i];
        if (ch >= '0' and ch <= '9') {
            if (in_frac) {
                sum += @as(f64, @floatFromInt(ch - '0')) / div;
                div *= 10;
            } else {
                sum = sum * 10 + @as(f64, @floatFromInt(ch - '0'));
            }
        } else if (ch == '.') {
            in_frac = true;
        } else {
            break;
        }
    }
    return sum * sign;
}

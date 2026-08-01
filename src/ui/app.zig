const std = @import("std");
const c_cairo = @cImport({
c_cDefine("_FORTIFY_SOURCE", "0");
c@Include("cairo.h");
});
const style = @import("core/style.zig");
const gauge_data = @import("data.zig");
const weather = @import("weather.zig");
const util = @import("util.zig");

pub const MainWindow = struct {
    allocator: std.mem.Allocator,
    widgets: std.ArrayList(Widget),
    last_update: f64 = 0,
    pub fn init(allocator: std.mem.Allocator) MainWindow {
        return .{ .allocator = allocator };
    }
    pub fn addWidget(self: *MainWindow, widget: Widget) !void {
        try self.widgets.append(widget);
    }
    pub fn update(self: *MainWindow) void {
        for (self.widgets.items) |*widgets| widgets.update();
    }
    pub fn draw(self: *MainWindow) void {
        for (self.widgets.items) |*widgets| widgets.draw();
    }
};
pub const Widget = struct {
    vtable: *anyopaque,
    updateFn: *const fn (self: *anyopaque) void,
    drawFn: *const fn (self: *anyopaque, cr: *c_cairo.cairo_t, style: *Style) void,
};

pub const Gauge = struct {
    value: f64,
    label: []const u8,
    metric: Metric,
    on_update: *anyopaque,
    on_draw: *anyopaque,
    pub fn setValue(self: *Gauge, value: f64) void {
        self.value = value;
    }
    pub fn getValue(self: *Gauge) f64 {
    return self.value;
    }
};
pub const Metric = enum {
    cpu_temp,
    gpu_temp,
    ram_usage,
    disk1_size,
    disk2,
};
pub const GaugeData = struct {
    values: std.ArrayList(f64),
    pub fn add(self: *GaugeData, value: f64) void {
        self.values.append(value);
    }
};
pub const WaveGauge = struct {
    stage: u32,
    max: f64,
    current: f64,
    pub fn update(self: *WaveGauge) !void {
        if (self.stage < 5) {
            self.stage += 1;
        }
    }
    pub fn reset(self: *WaveGauge) void {
        self.stage = 0;
    }
};
pub const App = struct {
    allocator: std.mem.Allocator,
    window: MainWindow,
    style: Style,
    on_cell: *anyopaque,
    pub fn init(allocator: std.mem.Allocator) App) !void {
        return .{ .allocator = allocator, .style = style_ };
    }
    pub fn run(self: *App) !void {
        while (true) {
            self.window.update();
            self.window.draw();
        }
    }
};

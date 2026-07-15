# Wallpaper / desktop background in KidulWM

Verified approach for loading an image into the root scene as the desktop background. Foundation for future screen-settings management (per-output images, brightness, fill modes).

## When to use

- Adding a static wallpaper background to KidulWM.
- Replacing the solid `color_background` root rect with an image buffer.
- Future work: IPC-driven wallpaper swap, per-output scaling, fill-mode enum.

## Design

- Keep the implementation in Zig.
- Use Cairo's built-in PNG reader (`cairo_image_surface_create_from_png`) to decode the image.
- Convert the ARGB32 pixels to a wlroots `Buffer` via `DataBuffer`.
- Attach that buffer to a `wlr.SceneBuffer` in the root scene tree, before/behind all windows.
- Resize/reposition the buffer on every output-layout change.
- Continue to use a solid-colour `SceneRect` as the fallback when the image is missing or fails to decode.

## Files touched

- `src/render/image.zig` — PNG loader wrapper.
- `src/render/buffer.zig` — `DataBuffer` already exists; consumes Cairo-native ARGB data.
- `src/server.zig` — owns the background state, loads the image, handles layout changes.

## Reference implementation

### 1. PNG loader wrapper

`src/render/image.zig`:

```zig
const std = @import("std");
const c = @import("../dm/c.zig").c;

pub const Image = struct {
    pub const Owned = struct {
        surface: ?*c.cairo_surface_t,
        data: []u8,
        width: i32,
        height: i32,
        stride: i32,

        pub fn deinit(self: Owned) void {
            c.cairo_surface_destroy(self.surface);
        }
    };

    pub fn loadPng(path: []const u8) !Owned {
        // Cairo's C API needs a null-terminated path.
        const path_z = try std.heap.page_allocator.dupeZ(u8, path);
        defer std.heap.page_allocator.free(path_z);

        const surface = c.cairo_image_surface_create_from_png(path_z.ptr);
        if (surface == null) return error.OutOfMemory;

        const status = c.cairo_surface_status(surface);
        if (status != c.CAIRO_STATUS_SUCCESS) {
            c.cairo_surface_destroy(surface);
            return error.CairoError;
        }

        const format = c.cairo_image_surface_get_format(surface);
        if (format != c.CAIRO_FORMAT_ARGB32) {
            c.cairo_surface_destroy(surface);
            return error.UnsupportedFormat;
        }

        c.cairo_surface_flush(surface);

        const width = c.cairo_image_surface_get_width(surface);
        const height = c.cairo_image_surface_get_height(surface);
        const stride = c.cairo_image_surface_get_stride(surface);
        const data_ptr = c.cairo_image_surface_get_data(surface);
        if (width <= 0 or height <= 0 or data_ptr == null) {
            c.cairo_surface_destroy(surface);
            return error.InvalidImage;
        }

        const data = @as([*]u8, @ptrCast(data_ptr))[0..@intCast(stride * height)];

        return .{
            .surface = surface,
            .data = data,
            .width = width,
            .height = height,
            .stride = stride,
        };
    }
};
```

### 2. Server background state

Extend the existing `Server.background` field to hold either a colour rect or an image buffer:

```zig
background: struct {
    color: [4]f32,
    node: ?*wlr.SceneNode,
    rect: ?*wlr.SceneRect,
    image_buffer: ?*wlr.Buffer,
    image_scene_buffer: ?*wlr.SceneBuffer,
    image_path: ?[]const u8,
},
```

Notes on ownership:

- `node` is the currently active background node (rect or image) for position updates.
- `image_buffer` keeps a compositor-owned reference to the image buffer. `DataBuffer.create` copies the Cairo pixels, so the underlying pixels stay alive as long as the `DataBuffer` reference count ≥ 1.
- `image_scene_buffer` lets us resize the displayed image with `setDestSize` on layout changes.

### 3. Initial setup

After the root scene tree exists, create the fallback rect and load the wallpaper:

```zig
const bg_rect = try server.scene.tree.createSceneRect(1, 1, &server.background.color);
server.background.rect = bg_rect;
server.background.node = &bg_rect.node;

server.loadWallpaper("/home/kidul/Pictures/Wallpapers/kidulBG01.png") catch |err| {
    std.log.warn("KidulWM: failed to load wallpaper, using fallback color: {}", .{err});
};
```

### 4. `loadWallpaper`

```zig
fn loadWallpaper(self: *Server, path: []const u8) !void {
    // Tear down the previous background node.
    if (self.background.node) |node| {
        node.destroy();
        self.background.node = null;
    }
    // Drop any previous image buffer reference. If the scene buffer owns its own
    // reference, this Decrement is harmless.
    if (self.background.image_buffer) |buffer| {
        wlr.Buffer.drop(buffer);
        self.background.image_buffer = null;
        self.background.image_scene_buffer = null;
    }

    const image = render_image.Image.loadPng(path) catch |err| {
        std.log.warn("KidulWM: failed to load wallpaper '{s}': {}", .{ path, err });
        const rect = try self.scene.tree.createSceneRect(1, 1, &self.background.color);
        self.background.rect = rect;
        self.background.node = &rect.node;
        return;
    };
    defer image.deinit();

    const buffer = try DataBuffer.create(image.data, image.width, image.height, image.stride);
    errdefer wlr.Buffer.drop(buffer);

    const tree = try self.scene.tree.createSceneTree();
    errdefer tree.node.destroy();

    const scene_buffer = try tree.createSceneBuffer(buffer);
    // wlroots' create path takes a reference on the buffer. Keep our own
    // reference as well via `image_buffer`; drop the temporary constructor ref.
    wlr.Buffer.drop(buffer);

    scene_buffer.setDestSize(image.width, image.height);

    self.background.rect = null;
    self.background.image_buffer = buffer;
    self.background.image_scene_buffer = scene_buffer;
    self.background.image_path = path;
    self.background.node = &scene_buffer.node;

    std.log.info("KidulWM: loaded wallpaper '{s}' ({d}x{d})", .{ path, image.width, image.height });
}
```

### 5. Respond to output-layout changes

```zig
fn handleOutputLayoutChange(...
    var box: wlr.Box = undefined;
    self.output_layout.getBox(null, &box);
    self.updateBackgroundLayout(&box);
    ...
}

fn updateBackgroundLayout(self: *Server, box: *const wlr.Box) void {
    if (self.background.node) |node| {
        node.setPosition(box.x, box.y);
    }
    if (self.background.image_scene_buffer) |scene_buffer| {
        scene_buffer.setDestSize(box.width, box.height);
    } else if (self.background.rect) |rect| {
        rect.setSize(box.width, box.height);
    }
}
```

## Known pitfalls

1. **Cairo `cairo_image_surface_create_from_png` needs a null-terminated path.** A raw Zig `[]const u8` is not null-terminated; use `std.heap.page_allocator.dupeZ(u8, path)` (and free it). Without this, the load may fail silently or with `CAIRO_STATUS_FILE_NOT_FOUND`.

2. **Buffer reference counting.** `wlr_scene_buffer_create` / `createSceneBuffer` in wlroots locks the buffer. Dropping the constructor reference immediately is correct *if* the scene buffer is attached to the scene. Retain a separate `image_buffer` field for the compositor's own bookkeeping and to ensure the buffer survives until the next wallpaper replace. If the image renders nowhere or appears as a flat black/empty area, first check that:
   - the path is null-terminated,
   - the buffer was created at the correct width/height/stride,
   - `setDestSize` was called on the scene buffer.

3. **Dark wallpapers look like no wallpaper.** The file `kidulBG01.png` has average lightness ~20/255, so it blends into the dark theme. Confirm image load with the log line or by temporarily using a bright test PNG. Don't chase a rendering bug when the image is simply very dark.

4. **Attach the image SceneBuffer directly to the root scene tree.** Creating an intermediate `SceneTree` and placing the SceneBuffer inside it can fail to render the image (only the fallback colour shows). The working approach is `self.scene.tree.createSceneBuffer(buffer)` and store `self.background.node = &scene_buffer.node`. Remove the `wlr.Buffer.drop(buffer)` if you also keep `image_buffer` for later replacement; otherwise drop it after creating the scene buffer.

5. **Pixel format must be `CAIRO_FORMAT_ARGB32`.** Error out for other formats rather than silently converting; cross-format conversion is out of scope for the minimal implementation.

## Future extensions

- Replace `image_path: ?[]const u8` with a config struct that includes fill mode (`fill`, `contain`, `stretch`, `tile`) and per-output overrides.
- Add IPC `set_background <path>` handler that calls `loadWallpaper` and triggers a layout pass.
- Add a brightness/Gamma multiplier as a separate `wlr.SceneRect` with a multiplicative blend mode, or apply it during pixel upload.
- For multi-output setups, create one background node per output inside the output's `SceneOutput` tree instead of a single layout-sized node.

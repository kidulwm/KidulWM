# Wallpaper cherry-pick recipe for KidulWM `29b8c55`

## When to use this

You want the PNG wallpaper background that existed in the WIP commit `774aaa8`,
but `774aaa8` also contains broken geometry/chrome changes that must not be
reintroduced. This recipe adds **only** the wallpaper support on top of a clean
`29b8c55` checkout and leaves `src/render/chrome.zig` and `src/window.zig`
untouched.

## Base state

```bash
cd /home/dad/dev/KidulWM
git checkout 29b8c55 -- .
git reset --hard 29b8c55
```

## Files to create/change

1. Create `src/render/image.zig` from the WIP commit:

```bash
git show 774aaa8:src/render/image.zig > src/render/image.zig
```

2. Patch `src/server.zig` with the four blocks below. Do **not** take the rest
   of the `774aaa8` server diff (it removes `setSurfaceDestSize` for focused
   windows and changes surface offset/clip logic).

### Imports

```zig
const chrome_renderer = @import("render/chrome.zig");
const render_image = @import("render/image.zig");
const DataBuffer = @import("render/buffer.zig").DataBuffer;
```

### Background struct

```zig
background: struct {
    node: ?*wlr.SceneNode,
    color: [4]f32,
    rect: ?*wlr.SceneRect,
    image_buffer: ?*wlr.Buffer,
    image_scene_buffer: ?*wlr.SceneBuffer,
},
```

### Init block

```zig
.background = .{
    .node = null,
    .rect = null,
    .color = style.default_style.color_background.toF32(),
    .image_buffer = null,
    .image_scene_buffer = null,
},
```

then after `server.outputs.init();`:

```zig
const bg_rect = try server.scene.tree.createSceneRect(1, 1, &server.background.color);
server.background.rect = bg_rect;
server.background.node = &bg_rect.node;

server.loadWallpaper("/home/kidul/Pictures/Wallpapers/kidulBG01.png") catch |err| {
    std.log.warn("KidulWM: failed to load wallpaper, using fallback color: {}", .{err});
};
```

### Replace `handleOutputLayoutChange`

```zig
fn handleOutputLayoutChange(listener: *wl.Listener(*wlr.OutputLayout), output_layout_arg: *wlr.OutputLayout) void {
    const self: *Server = @fieldParentPtr("output_layout_change", listener);
    _ = output_layout_arg;

    var box: wlr.Box = undefined;
    self.output_layout.getBox(null, &box);
    self.updateBackgroundLayout(&box);

    self.requestLayout();
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

fn loadWallpaper(self: *Server, path: []const u8) !void {
    if (self.background.node) |node| {
        node.destroy();
        self.background.node = null;
    }
    if (self.background.image_buffer) |buffer| {
        wlr.Buffer.drop(buffer);
        self.background.image_buffer = null;
        self.background.image_scene_buffer = null;
    }

    const image = render_image.Image.loadPng(path) catch |err| {
        std.log.warn("KidulWM: failed to load wallpaper '{s}': {}", .{ path, err });
        const rect = try self.scene.tree.createSceneRect(1, 1, &self.background.color);
        self.background.rect = rect;
        self.background.image_scene_buffer = null;
        self.background.node = &rect.node;
        return;
    };
    defer image.deinit();

    const buffer = try DataBuffer.create(image.data, image.width, image.height, image.stride);
    errdefer wlr.Buffer.drop(buffer);

    const scene_buffer = try self.scene.tree.createSceneBuffer(buffer);
    scene_buffer.setDestSize(image.width, image.height);

    self.background.rect = null;
    self.background.image_buffer = buffer;
    self.background.image_scene_buffer = scene_buffer;
    self.background.node = &scene_buffer.node;

    std.log.info("KidulWM: loaded wallpaper '{s}' ({d}x{d})", .{ path, image.width, image.height });
}
```

### Update `applyTheme` color fallback

```zig
self.background.color = self.theme.color_background.toF32();
if (self.background.image_scene_buffer == null) {
    if (self.background.rect) |rect| {
        rect.setColor(&self.background.color);
    }
}
self.requestLayout();
```

## Verify geometry files are untouched

```bash
git diff 29b8c55 -- src/render/chrome.zig src/window.zig
# should produce no output
```

## Build, copy wallpaper, deploy

```bash
zig build
ssh -p 2222 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 'mkdir -p /home/kidul/Pictures/Wallpapers'
scp -P 2222 -i ~/.ssh/id_ed25519_kidulwm \
  ~/Pictures/Wallpapers/kidulBG01.png \
  kidul@127.0.0.1:/home/kidul/Pictures/Wallpapers/kidulBG01.png
scp -P 2222 -i ~/.ssh/id_ed25519_kidulwm \
  zig-out/bin/kidulwm kidul@127.0.0.1:/tmp/kidulwm.new
ssh -p 2222 -i ~/.ssh/id_ed25519_kidulwm kidul@127.0.0.1 \
  'sudo systemctl stop kidulwm && sudo cp /tmp/kidulwm.new /usr/bin/kidulwm && sudo chmod 755 /usr/bin/kidulwm && sudo systemctl start kidulwm && systemctl is-active kidulwm'
```

## Why this is safe

- `src/render/image.zig` is self-contained and only adds a PNG loader.
- The server changes extend the existing `Server.background` rect with an optional image node.
- No window geometry, chrome mask, clip, or surface offset logic changes.
- If the PNG load fails, the original solid-colour background rect is recreated.

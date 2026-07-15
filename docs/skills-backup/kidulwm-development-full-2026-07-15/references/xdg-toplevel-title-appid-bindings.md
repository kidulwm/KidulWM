# XdgToplevel `title` / `app_id` access in zig-wlroots

Authoritative binding shape for wlroots 0.20.x as exposed by the zig-wlroots package used by KidulWM.

```zig
pub const XdgToplevel = extern struct {
    title: ?[*:0]u8,
    app_id: ?[*:0]u8,
    events: extern struct {
        set_title: wl.Signal(void),
        set_app_id: wl.Signal(void),
    },
};
```

## Reading the strings

Both fields are nullable null-terminated C strings. Convert safely:

```zig
if (toplevel.title) |ptr| {
    const slice = std.mem.sliceTo(ptr, 0);
    // copy or inspect slice
}
```

## Listening for changes

`set_title` and `set_app_id` carry no payload; the handler must re-read the field:

```zig
const set_title = wl.Listener(void).init(handleSetTitle);
toplevel.events.set_title.add(&set_title);

fn handleSetTitle(listener: *wl.Listener(void)) void {
    const window: *Window = @fieldParentPtr("set_title", listener);
    if (window.toplevel.title) |ptr| {
        const s = std.mem.sliceTo(ptr, 0);
        _ = window.title.set(s);
    }
    window.chromeNeedsRegen();
}
```

## Use cases

- Window titles for internal UI / trays.
- `app_id`-driven rules (per-app nicknames, tiling hints, forced CSD/SSD).
- Fallback label text when `app_id` is empty.

## Gotchas

- The strings are owned by wlroots; do not keep raw pointers past the event. Copy into owned buffers.
- Events fire before the client commits the new state, so reading during `handleCommit` is usually too early for the just-set value.
- `toplevel.base.surface` is separate from `toplevel`; do not confuse window metadata signals with surface commit signals.

# Reviving the archived chamfer branch — stale `createPixman()` binding

## Context

The `.cut` chamfer code was archived to `archive/chamfer-cachyos` and tag `chamfer-final-cachyos` before the CachyOS branch switched to rounded corners. The archived branch's last commit (`bb13c77`) predates the current flurry of renderer workarounds.

## Build error

When checked out into a fresh worktree and built against the current `zig-wlroots` 0.20.1 dependency, `src/server.zig` fails with:

```
error: struct 'render.renderer.Renderer' has no member named 'createPixman'
```

The code uses:

```zig
const renderer = if (force_pixman)
    try wlr.Renderer.createPixman()
else
    try wlr.Renderer.autocreate(backend);
```

## Why

The current `zig-wlroots` 0.20.1 bindings do not expose `wlr_pixman_renderer_create()` as `Renderer.createPixman()`. The function exists in `libwlroots-0.20.so` but lacks a Zig wrapper.

## Fix

Add the extern wrapper to the local vendored binding at `zig-pkg/wlroots-0.20.1-*/src/render/renderer.zig`:

```zig
extern fn wlr_pixman_renderer_create() ?*Renderer;
pub fn createPixman() !*Renderer {
    return wlr_pixman_renderer_create() orelse error.RendererCreateFailed;
}
```

Place it near the other renderer constructor declarations (e.g., after the `isPixman` / `isGles2` lines).

## Workflow for quick chamfer experiments

1. Create a git worktree from `archive/chamfer-cachyos` so the main repo is untouched.
2. Apply the `createPixman()` binding patch if needed.
3. Apply any modern fixes you want to test (e.g., `bg_rect` removal) to the worktree.
4. Build, then deploy to a disposable VM clone built from the known-good running VM.
5. Do **not** merge the chamfer branch back into the CachyOS main branch unless the user explicitly requests a permanent return to chamfers.

## Remember

The archived branch is for exploration only. The long-term home for chamfers is the future Gentoo premium build; revive it in the CachyOS branch only as a throwaway experiment.

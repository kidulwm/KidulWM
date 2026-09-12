const std = @import("std");
const linux = std.os.linux;
const wlr = @import("wlroots");
const DataBuffer = @import("../render/buffer.zig").DataBuffer;
const DmabufBuffer = @import("../render/dmabuf_buffer.zig").DmabufBuffer;
const kmedia_lib = @import("kmedia");
const server_mod = @import("../server.zig");

const Server = server_mod.Server;
const Output = server_mod.Output;

// ── Media slide video presentation ───────────────────────────────────────────
// kvis.md LAW: "the media slide is just a slide" — the per-output slide
// container owns video presentation state (dmabuf_cache, video scene nodes,
// display serial, generation). server.zig keeps only thin delegations.
// [media]/[present] log lines stay byte-identical (census tooling parses
// them).

/// Reset the [present] counters (new playback / teardown).
fn presentReset(output: *Output) void {
    const ms = &output.media_slide;
    ms.present_committed = 0;
    ms.present_dropped = 0;
    ms.present_hit = 0;
    ms.present_miss = 0;
    ms.present_memcpy = 0;
    ms.present_late_sum_ms = 0;
    ms.present_late_max_ms = 0;
    ms.present_bucket_us = 0;
}

/// Update the dedicated video scene buffer from the player's current
/// frame. Called on each frame_serial bump while player_active. Only the
/// video pixels are copied (native size); the scene graph scales to the
/// letterboxed rect. No full-slide repaint, no 8MB DataBuffer dupe.
pub fn refresh(server: *Server, output: *Output) void {
    const tree = output.media_slide.tree orelse {
        std.log.info("[media] refresh SKIP: no slide tree", .{});
        return;
    };
    const widget = &output.media_slide.widget;
    if (!widget.player_active) {
        std.log.info("[media] refresh SKIP: player_active=false gen={d}", .{widget.player_generation});
        return;
    }
    const deck = &output.deck;
    // Video plays fullscreen (playback.md): the letterbox target is the
    // full output rect while the player is active.
    const target = deck.mediaSlideTarget(true);

    // GENERATION GUARD (structural): the dmabuf cache is keyed on
    // (surface, gen), but the live video_buffer node may still point
    // at a stale-gen buffer when a stop/reopen slipped past every
    // call-site teardown. Tear down before presenting — a stale node
    // can never reach the screen.
    if (widget.player_generation != output.media_slide.seen_player_generation) {
        std.log.info("[media] GEN-GUARD refresh: gen={d} seen={d} -> teardown", .{ widget.player_generation, output.media_slide.seen_player_generation });
        output.media_slide.seen_player_generation = widget.player_generation;
        teardown(server, output);
    }

    // ── ZERO-COPY DMABUF BRANCH ─────────────────────────────────────
    // If the player is in hw zero-copy mode, import the displayed VA
    // surface as a dmabuf wlr.Buffer and hand it straight to the scene
    // graph — no per-frame CPU copy. ANY failure falls through to the
    // memcpy path silently; the next frame may succeed. A failed frame
    // redraws the last good image (black-with-sound is dead law).
    if (widget.player.currentVaFrame()) |va_frame| {
        if (dmabufRefresh(output, va_frame)) {
            // [present] commit: zero-copy dmabuf frame placed on the
            // output. Lateness proxy = audio clock − frame pts at the
            // display edge (target present ≈ pts on the audio clock).
            const surface_id: u32 = @intCast(@intFromPtr(va_frame.data[3]));
            output.media_slide.present_committed += 1;
            const late_ms: i64 = @divTrunc(widget.player.audio_pts_us - widget.player.displayed_pts_us, 1000);
            output.media_slide.present_late_sum_ms += late_ms;
            if (late_ms > output.media_slide.present_late_max_ms) output.media_slide.present_late_max_ms = late_ms;
            if (output.media_slide.present_committed <= 16 or @rem(output.media_slide.present_committed, 120) == 0) {
                std.log.info("[present] surface=0x{x} gen={d} cache={s} late={d}ms serial={d}", .{
                    surface_id,
                    widget.player_generation,
                    if (output.media_slide.last_dmabuf_hit) @as([]const u8, "hit") else "miss",
                    late_ms,
                    widget.player.display_serial,
                });
            }
            // Position/scale into the output rect below (shared with
            // the memcpy path's tail).
            const sb = output.media_slide.video_buffer orelse return;
            const tw: f64 = @floatFromInt(target.width);
            const th: f64 = @floatFromInt(target.height);
            const vw: f64 = @floatFromInt(sb.buffer.?.width);
            const vh: f64 = @floatFromInt(sb.buffer.?.height);
            const scale = @min(tw / vw, th / vh);
            const dw: i32 = @intFromFloat(vw * scale);
            const dh: i32 = @intFromFloat(vh * scale);
            const tw_i: i32 = @intCast(target.width);
            const th_i: i32 = @intCast(target.height);
            const dx: i32 = @divTrunc(tw_i - dw, 2) + target.x;
            const dy: i32 = @divTrunc(th_i - dh, 2) + target.y;
            sb.setDestSize(dw, dh);
            sb.node.setPosition(dx, dy);
            if (output.media_slide.card_buffer) |card| card.node.raiseToTop();
            return;
        }
    }

    // ── memcpy fallback (sw decode OR dmabuf import failed) ─────────
    const frame = widget.player.currentFrame() orelse {
        if (output.media_slide.dmabuf_fail_logs < 8) {
            output.media_slide.dmabuf_fail_logs += 1;
            std.log.info("[media] refresh NULL: no va_frame and no sw frame (gen={d} serial={d})", .{ widget.player_generation, widget.player.display_serial });
        }
        return;
    };

    // (Re)allocate the persistent pixel buffer if size changed.
    const need: usize = @intCast(frame.stride * frame.h);
    if (output.media_slide.video_pixels.len != need) {
        // BLACK-WITH-SOUND LAW: if the previous video node held a live
        // dmabuf (zero-copy cache), keep it on screen until the memcpy
        // buffer is ready to replace it — a transient export failure
        // must redraw the last good image, never blink to the card hole.
        const had_dmabuf = output.media_slide.video_wlr_buf == null and output.media_slide.video_buffer != null;
        if (!had_dmabuf) {
            if (output.media_slide.video_buffer) |sb| {
                sb.node.destroy();
                output.media_slide.video_buffer = null;
            }
        }
        if (output.media_slide.video_wlr_buf) |old| {
            wlr.Buffer.drop(old);
            output.media_slide.video_wlr_buf = null;
        }
        server.allocator.free(output.media_slide.video_pixels);
        output.media_slide.video_pixels = server.allocator.alloc(u8, need) catch return;
    }

    // Copy the frame rows (respect stride).
    const row_bytes: usize = @intCast(frame.w * 4);
    var row: usize = 0;
    while (row < @as(usize, @intCast(frame.h))) : (row += 1) {
        const src_off = row * @as(usize, @intCast(frame.stride));
        @memcpy(output.media_slide.video_pixels[src_off .. src_off + row_bytes], frame.data[src_off .. src_off + row_bytes]);
    }

    // (Re)create the wlroots buffer wrapper if needed. Zero-copy ref:
    // the scene graph reads our video_pixels memory directly; we rewrite
    // it in place each frame. No 8MB dupe.
    if (output.media_slide.video_wlr_buf == null) {
        const buf = DataBuffer.createRef(
            output.media_slide.video_pixels,
            frame.w,
            frame.h,
            frame.stride,
        ) catch return;
        output.media_slide.video_wlr_buf = buf;
    }

    // (Re)create the scene buffer node if needed.
    if (output.media_slide.video_buffer == null) {
        const sb = tree.createSceneBuffer(output.media_slide.video_wlr_buf) catch return;
        output.media_slide.video_buffer = sb;
    } else {
        output.media_slide.video_buffer.?.setBuffer(output.media_slide.video_wlr_buf);
    }

    const sb = output.media_slide.video_buffer.?;
    // PLAYBACK FULLSCREEN LAW: while playing, the slide tree sits at
    // 0,0 and the card buffer IS the full output (see mediaSlideRefresh),
    // so the video letterboxes straight into the output rect — no
    // slide-local shifting. Covers the peeks, normal FULL SCREEN.
    const tw: f64 = @floatFromInt(target.width);
    const th: f64 = @floatFromInt(target.height);
    const vw: f64 = @floatFromInt(frame.w);
    const vh: f64 = @floatFromInt(frame.h);
    const scale = @min(tw / vw, th / vh);
    const dw: i32 = @intFromFloat(vw * scale);
    const dh: i32 = @intFromFloat(vh * scale);
    const tw_i: i32 = @intCast(target.width);
    const th_i: i32 = @intCast(target.height);
    const dx: i32 = @divTrunc(tw_i - dw, 2) + target.x;
    const dy: i32 = @divTrunc(th_i - dh, 2) + target.y;
    sb.setDestSize(dw, dh);
    sb.node.setPosition(dx, dy);
    // [present] commit: memcpy (sw decode or dmabuf fallback) frame.
    output.media_slide.present_committed += 1;
    output.media_slide.present_memcpy += 1;
    const late_ms: i64 = @divTrunc(widget.player.audio_pts_us - widget.player.displayed_pts_us, 1000);
    output.media_slide.present_late_sum_ms += late_ms;
    if (late_ms > output.media_slide.present_late_max_ms) output.media_slide.present_late_max_ms = late_ms;
    if (output.media_slide.present_committed <= 16 or @rem(output.media_slide.present_committed, 120) == 0) {
        std.log.info("[present] memcpy gen={d} cache=na late={d}ms serial={d}", .{
            widget.player_generation,
            late_ms,
            widget.player.display_serial,
        });
    }
    // Z-ORDER: the video buffer sits BELOW the card buffer. The card's
    // Player.render (embedder_owns_video) paints the black matte + chrome
    // but leaves the video rect transparent, so the video shows through
    // the hole while the progress bar / buttons stay visible on top.
    if (output.media_slide.card_buffer) |card| card.node.raiseToTop();
}

/// Zero-copy dmabuf import of the player's displayed VA frame into the
/// video scene buffer. Returns true when the scene buffer now holds a
/// live dmabuf; false → caller falls through to the memcpy path
/// (silently, per-frame). Mirrors the lab's three doors in Gl.zig:
/// door A = separate-layers export, door B = composed-layers whole
/// surface. Per-frame failure keeps the last good buffer on screen.
pub fn dmabufRefresh(output: *Output, va_frame: *kmedia_lib.av.AVFrame) bool {
    const av = kmedia_lib.av;
    const tree = output.media_slide.tree orelse return false;

    // VA surface id from the hw frame (Player owns the frame; we never
    // free it — borrowed ref per currentVaFrame()).
    const surface_id: u32 = @intCast(@intFromPtr(va_frame.data[3]));

    // CACHE HIT: this pool surface was already exported+imported on an
    // earlier frame — just point the shared scene node at its buffer.
    // A hit requires BOTH the surface id AND the player generation
    // that imported it: VA pools reuse surface ids across decoders, so
    // a surface-only key can alias the DEAD decoder's freed surfaces
    // (the second-video blank/freeze). gen makes a stale hit
    // structurally impossible — no call-site guard can miss it.
    const gen = output.media_slide.widget.player_generation;
    for (&output.media_slide.dmabuf_cache) |*entry| {
        if (entry.buf != null and entry.surface == surface_id and entry.gen == gen) {
            output.media_slide.present_hit += 1;
            output.media_slide.last_dmabuf_hit = true;
            // RENDER-ONCE LAW (fd-leak fix, 2026-09-08): the lab
            // (Gl.zig) holds ONE import live and redraws it; the
            // slide's per-frame setBuffer() made wlroots destroy +
            // recreate the texture every frame and its dmabuf attribs
            // copy leaked fds (render/dmabuf.c F_DUPFD_CLOEXEC →
            // EMFILE → compositor wedge → power-button freeze). Only
            // setBuffer when the scene node isn't already showing THIS
            // surface's buffer; steady-state playback re-points at the
            // same cached buffer and must NOT churn the texture.
            const sb = output.media_slide.video_buffer orelse blk: {
                const new_sb = tree.createSceneBuffer(entry.buf.?) catch return false;
                output.media_slide.video_buffer = new_sb;
                break :blk new_sb;
            };
            if (sb.buffer != entry.buf.?) sb.setBuffer(entry.buf.?);
            return true;
        }
    }

    const fctx: *av.AVHWFramesContext = @ptrCast(@alignCast(va_frame.hw_frames_ctx.*.data));
    const devctx: *av.AVHWDeviceContext = @ptrCast(@alignCast(fctx.device_ref.*.data));
    const dctx: *av.AVVAAPIDeviceContext = @ptrCast(@alignCast(devctx.hwctx));
    const va_display: av.VADisplay = dctx.display;

    // Doors A (separate) then B (composed) — the lab's door order;
    // do NOT reorder (iHD GR1616 quirk).
    const door_flags = [2]u32{
        av.VA_EXPORT_SURFACE_READ_ONLY | av.VA_EXPORT_SURFACE_SEPARATE_LAYERS,
        av.VA_EXPORT_SURFACE_READ_ONLY | av.VA_EXPORT_SURFACE_COMPOSED_LAYERS,
    };
    var door: usize = 0;
    while (door < 2) : (door += 1) {
        var va_desc: av.VADRMPRIMESurfaceDescriptor = std.mem.zeroes(av.VADRMPRIMESurfaceDescriptor);
        const rc = av.vaExportSurfaceHandle(va_display, surface_id, av.VA_SURFACE_ATTRIB_MEM_TYPE_DRM_PRIME_2, door_flags[door], &va_desc);
        if (rc != av.VA_STATUS_SUCCESS) {
            if (output.media_slide.dmabuf_fail_logs < 8) {
                output.media_slide.dmabuf_fail_logs += 1;
                std.log.info("[media] dmabuf FAIL door={s}: vaExportSurfaceHandle rc={d} surface=0x{x}", .{ if (door == 0) @as([]const u8, "A-sep") else "B-comp", rc, @intFromPtr(va_frame.data[3]) });
            }
            continue;
        }

        // Walk the descriptor into wlr.DmabufAttributes. We DUP the
        // object fds: the VA descriptor is closed right after this
        // block (closeVaDesc hygiene), while the wlr buffer must keep
        // valid fds for its own lifetime. wlroots does NOT take
        // ownership of fds handed via wlr_dmabuf_attributes — the
        // consumer dups again (wlr_dmabuf_attributes_copy) for the
        // EGLImage import, and wlr_dmabuf_attributes_finish closes
        // what it owns. Hence: dup here, close VA originals, buffer
        // destroy() finishes (closes) our dups.
        var attribs: wlr.DmabufAttributes = std.mem.zeroes(wlr.DmabufAttributes);
        attribs.width = va_frame.width;
        attribs.height = va_frame.height;
        attribs.format = va_desc.fourcc;
        attribs.modifier = va_desc.objects[0].drm_format_modifier;
        const n_layers: usize = @min(va_desc.num_layers, 4);
        var n_planes: usize = 0;
        var ok = true;
        for (0..n_layers) |layer_i| {
            const layer = &va_desc.layers[layer_i];
            for (0..@min(layer.num_planes, 4)) |plane_i| {
                if (n_planes >= 4) {
                    ok = false;
                    break;
                }
                attribs.offset[n_planes] = layer.offset[plane_i];
                attribs.stride[n_planes] = layer.pitch[plane_i];
                attribs.fd[n_planes] = std.c.dup(va_desc.objects[layer.object_index[plane_i]].fd);
                if (attribs.fd[n_planes] < 0) {
                    ok = false;
                    break;
                }
                n_planes += 1;
            }
            if (!ok) break;
        }
        // closeVaDesc: always close the VA originals now.
        for (0..va_desc.num_objects) |i| _ = linux.close(va_desc.objects[i].fd);

        if (!ok or n_planes == 0) {
            for (0..n_planes) |i| _ = linux.close(attribs.fd[i]);
            continue;
        }
        attribs.n_planes = @intCast(n_planes);

        // Single modifier across planes (all objects share the same
        // tiling on iHD; wlroots takes ONE modifier per buffer).
        // Per-object mismatch → give up on this door quietly.
        var mod_ok = true;
        for (1..va_desc.num_objects) |i| {
            if (va_desc.objects[i].drm_format_modifier != attribs.modifier) mod_ok = false;
        }
        if (!mod_ok) {
            for (0..n_planes) |i| _ = linux.close(attribs.fd[i]);
            continue;
        }

        const buf = DmabufBuffer.create(&attribs) catch |err| {
            if (output.media_slide.dmabuf_fail_logs < 8) {
                output.media_slide.dmabuf_fail_logs += 1;
                std.log.info("[media] dmabuf FAIL door={s}: createBuffer err={s} fourcc=0x{x} planes={d} mod=0x{x} {d}x{d}", .{ if (door == 0) @as([]const u8, "A-sep") else "B-comp", @errorName(err), attribs.format, n_planes, attribs.modifier, attribs.width, attribs.height });
            }
            for (0..n_planes) |i| _ = linux.close(attribs.fd[i]);
            continue;
        };

        // Import succeeded: park this surface's buffer in the cache.
        // Slot choice: first free slot, else first STALE-GEN slot (its
        // decoder is dead — the buffer will never hit again), else the
        // oldest slot (pool is small, same-gen eviction should never
        // happen mid-stream).
        var slot: ?*@TypeOf(output.media_slide.dmabuf_cache[0]) = null;
        for (&output.media_slide.dmabuf_cache) |*entry| {
            if (entry.buf == null) {
                slot = entry;
                break;
            }
            if (slot == null and entry.gen != gen) slot = entry;
        }
        const s = slot orelse &output.media_slide.dmabuf_cache[0];
        if (s.buf) |old| wlr.Buffer.drop(old);
        s.* = .{ .surface = surface_id, .gen = gen, .buf = buf };
        output.media_slide.present_miss += 1;
        output.media_slide.last_dmabuf_hit = false;

        if (output.media_slide.video_buffer) |sb| {
            sb.setBuffer(buf);
        } else {
            const sb = tree.createSceneBuffer(buf) catch {
                s.* = .{};
                wlr.Buffer.drop(buf);
                continue;
            };
            output.media_slide.video_buffer = sb;
        }

        if (!output.media_slide.dmabuf_logged) {
            output.media_slide.dmabuf_logged = true;
            std.log.info("[media] dmabuf zero-copy live (fourcc=0x{x}, {s} layers, planes={d}, mod=0x{x})", .{
                attribs.format,
                if (door == 0) "separate" else "composed",
                n_planes,
                attribs.modifier,
            });
        }
        return true;
    }
    return false;
}

/// Kill the live video scene path: scene node, wlr buffer ref, and the
/// persistent pixel copy. Called whenever playback stops (ensureStopped)
/// so the last frame does NOT linger as a ghost behind the wall and
/// other windows. Safe to call when already torn down.
pub fn teardown(server: *Server, output: *Output) void {
    // SCENE LOCK LAW: callers must hold scene_mutex (mediaSlideClose
    // on the IPC thread; handleFrame on the render thread; Output.deinit
    // on the main thread at teardown). Never lock here — nested.
    if (output.media_slide.video_buffer) |sb| sb.node.destroy();
    output.media_slide.video_buffer = null;
    if (output.media_slide.video_wlr_buf) |buf| wlr.Buffer.drop(buf);
    output.media_slide.video_wlr_buf = null;
    if (output.media_slide.video_pixels.len > 0) {
        server.allocator.free(output.media_slide.video_pixels);
        output.media_slide.video_pixels = &.{};
    }
    output.media_slide.last_display_serial = 0;
    output.media_slide.dmabuf_logged = false;
    output.media_slide.dmabuf_fail_logs = 0;
    presentReset(output);
    for (&output.media_slide.dmabuf_cache) |*entry| {
        if (entry.buf) |buf| wlr.Buffer.drop(buf);
        entry.* = .{};
    }
}

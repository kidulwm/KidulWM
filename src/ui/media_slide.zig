const std = @import("std");
const wlr = @import("wlroots");
const cairo = @import("dm").c;
const Style = @import("../core/style.zig").Style;
const media_mod = @import("media.zig");
const DataBuffer = @import("../render/buffer.zig").DataBuffer;

/// Compositor-owned media player slide: one scene tree per output holding
/// the Cairo-rendered media UI as a single buffer. Lives on the virtual
/// before_first deck slot (sibling of the after_last overview sentinel).
/// Not a window, never parked, INPUT LAW applies while open.
pub const MediaSlide = struct {
    tree: ?*wlr.SceneTree = null,
    card_buffer: ?*wlr.SceneBuffer = null,
    /// Widget state persists across open/close so the player remembers
    /// category/search/selection between visits.
    widget: media_mod.MediaWidget = undefined,
    widget_ready: bool = false,
    /// Last DISPLAY-edge serial we copied into the video scene buffer for;
    /// the frame handler ticks the player every vsync and only refreshes
    /// the video buffer when this moves.
    last_display_serial: u64 = 0,
    /// Card buffer geometry and content guard (verdict 17, 2026-09-12):
    /// mediaSlideRefresh is called from applyLayout on EVERY layout event
    /// (window focus, commit, etc.) while the slide is open. renderToBuffer
    /// allocates a 33MB ARGB32 surface each call; with many rapid re-fires
    /// the GPU pipeline holds multiple 33MB bufs simultaneously → ~20-35
    /// MB/s RSS growth in the prewarm window (active=false) → OOM.
    /// Guard: re-render only when the target rect changed OR card_dirty is
    /// set (set by any widget mutation that changes pixel content).
    /// The playing-branch already skips renderToBuffer entirely.
    card_last_w: i32 = 0,
    card_last_h: i32 = 0,
    card_dirty: bool = true,
    /// Widget state_generation at the last card render. When art loads or
    /// any widget mutation bumps state_generation, this diverges from the
    /// widget's current value and the guard treats it as dirty — so art
    /// appears on the card without needing explicit dirty-setting at every
    /// art-load call site. Initialised to max-value so the first render
    /// always fires (state_generation starts at 0 → always differs).
    card_last_gen: u32 = std.math.maxInt(u32),
    /// Dedicated scene buffer for the live video frame. Updated per-frame
    /// from Player.currentFrame(); the card buffer above carries only chrome.
    video_buffer: ?*wlr.SceneBuffer = null,
    video_wlr_buf: ?*wlr.Buffer = null,
    video_pixels: []u8 = &.{},
    /// Zero-copy dmabuf path state: one-time-per-stream log latch and the
    /// source size the live dmabuf buffer was created for (VA frames can
    /// arrive at native size while the memcpy path letterboxes).
    dmabuf_logged: bool = false,
    /// Failure-probe budget: log the first N dmabuf failures per playback
    /// (doorstep + error), then stay silent. Reset on teardown.
    dmabuf_fail_logs: u8 = 0,
    /// Whether the last mediaVideoDmabufRefresh call resolved via cache hit
    /// (vs a fresh export+import = miss). Read by the [present] commit log.
    last_dmabuf_hit: bool = false,
    /// Per-surface dmabuf buffer cache: VAAPI decodes through a small
    /// surface pool, so export+import ONCE per pool surface instead of
    /// every frame. Key = VASurfaceID; value = the wlr buffer holding the
    /// dup'd fds. The scene node is shared (video_buffer) — per frame we
    /// only setBuffer() the cached entry. Teardown drops all entries.
    /// SIZE LAW (2026-09-12 verdict 15): the cache MUST cover every
    /// surface that can be live at once: kmedia VIDEO_RING_SIZE (16) +
    /// the displayed frame + the decoder DPB refs (~4-8). At 8 slots the
    /// pool outgrew the cache the moment the ring went 8→16: EVERY frame
    /// missed → export+create+evict+setBuffer per frame → wlroots
    /// texture destroy/create churn leaked fds (render/dmabuf.c
    /// F_DUPFD_CLOEXEC → EMFILE ≈ 20s in → compositor dead, the "20s
    /// crash"). 32 slots = ring 16 + headroom; entries are tiny, the
    /// cost is the ~32 pinned GEM buffers we already paid at 16.
    dmabuf_cache: [32]DmabufCacheEntry = [_]DmabufCacheEntry{.{}} ** 32,

    /// Last widget player_generation the frame handler has seen; a mismatch
    /// means the player was stopped/reopened and every cached dmabuf buffer
    /// (keyed on reused VA surface IDs) is stale → teardown before use.
    seen_player_generation: u64 = 0,

    /// Presentation-timing instrumentation ([present] logs, aggregated 1s
    /// buckets, reset on teardown). Counts video frames committed to the
    /// scene, vsync periods with no new frame (drops), dmabuf cache
    /// hit/miss, and the worst lateness (audio clock − frame pts) in ms.
    present_committed: u32 = 0,
    present_dropped: u32 = 0,
    present_hit: u32 = 0,
    present_miss: u32 = 0,
    present_memcpy: u32 = 0,
    present_late_sum_ms: i64 = 0,
    present_late_max_ms: i64 = 0,
    present_bucket_us: i64 = 0,

    pub const DmabufCacheEntry = struct {
        surface: u32 = 0,
        /// Player generation that imported this entry (from the widget's
        /// player_generation at import time). A hit requires BOTH surface
        /// and gen match — VA pools reuse surface IDs across decoders, so
        /// surface alone can alias a dead decoder (second-video blank).
        gen: u64 = 0,
        buf: ?*wlr.Buffer = null,
    };

    pub fn isOpen(self: *const MediaSlide) bool {
        return self.tree != null;
    }

    /// Per-output playback driving, called once per vsync from
    /// Output.handleFrame (render thread, scene_mutex held). KVIS LAW:
    /// "the media slide is just a slide" — the slide owns its playback
    /// presentation state; server.zig only provides the lifecycle entries
    /// (mediaVideoRefresh/Teardown delegations, play timer, slide refresh).
    pub fn tickPlayback(self: *MediaSlide, server: anytype, output: anytype, now_us: u64) void {
        // ── Play-timer arm (reactive) ────────────────────────────────────
        // The compositor-level play_timer (Server.handlePlayTimer) owns
        // tick() and mediaVideoRefresh() — this output just presents whatever
        // frame is already due (see below). Arm the timer here the first time
        // we see player activity, so playback that starts while no timer is
        // running still gets clocked. The timer self-re-arms; a spurious extra
        // arm from a second output is harmless (timerUpdate resets the delay).
        //
        // Stage 2 — audio-clocked playloop (2026-09-07): advance is now driven
        // by a single compositor-level wl_event_loop timer, not by a specific
        // output's frame callback. Outputs only PRESENT the due frame on their
        // own vsync. See Server.handlePlayTimer, Server.armPlayTimer.
        const any_playing = (self.widget_ready and
            self.widget.player_active) or
            server.media_player.player_active;
        if (any_playing and server.play_timer == null) {
            server.armPlayTimer();
        }

        // ── isDone / no-stills teardown (render-thread guards) ───────────
        // The play_timer checks isDone too, but the render thread must also
        // guard here: if the timer fires and calls disarmPlayTimer between
        // vsync edges we still need to catch a done state and clean up scene
        // nodes (which must happen on the render thread while holding the lock).
        if (self.isOpen() and self.widget_ready and self.widget.player_active) {
            // PLAYER-INSTANCE GUARD: a stop/reopen cycle (second video)
            // bumps player_generation; the dmabuf cache is keyed on VA
            // surface IDs which the new decoder's pool reuses — drop all
            // compositor-side video state before touching the new player,
            // or a stale cache hit renders freed GPU surfaces (the 2026-09-08
            // power-button freeze).
            if (self.widget.player_generation != self.seen_player_generation) {
                self.seen_player_generation = self.widget.player_generation;
                server.mediaVideoTeardown(output);
            }
            if (self.widget.player.isDone()) {
                self.widget.ensureStopped();
                server.mediaVideoTeardown(output);
                server.disarmPlayTimer();
                // Player ended — refresh the card so the slide shrinks back
                // from fullscreen to its slot rect (media-collapse).
                self.card_dirty = true; // content changed: card must repaint
                server.mediaSlideRefresh(output);
            } else {
                // AUDIO-CLOCKED PLAYLOOP (main): tick() is owned by the
                // play_timer, NOT this per-output frame callback. Here we
                // only PRESENT what the playloop advanced.
                // VSYNC GRID (media-collapse): the play_timer's tick() carries
                // the interval; the display_serial check here is the
                // present-edge.
                const serial = self.widget.player.display_serial;
                if (serial != self.last_display_serial) {
                    self.last_display_serial = serial;
                    server.mediaVideoRefresh(output);
                } else {
                    // [present] DROP: video active on this vsync period but
                    // the playloop produced no new frame — the display edge
                    // will re-show the previous buffer.
                    self.present_dropped += 1;
                }
                server.presentAggregateFlush(output, now_us);
            }
        } else if (self.video_buffer != null) {
            // Reconcile: player stopped on a path the server didn't drive
            // (widget.update(), play() switching tracks, widget deinit) —
            // the ghost frame must not outlive playback. LAW: no stills.
            server.mediaVideoTeardown(output);
        }

        // ── Slideless isDone guard ───────────────────────────────────────
        // Mirror of the above for the tray music path (slide closed).
        if (!self.isOpen() and server.media_player.player_active) {
            if (server.media_player.player.isDone()) {
                server.media_player.ensureStopped();
                server.disarmPlayTimer();
            }
        }
    }

    pub fn ensureWidget(self: *MediaSlide, allocator: std.mem.Allocator) *media_mod.MediaWidget {
        if (!self.widget_ready) {
            self.widget = media_mod.MediaWidget.init(allocator);
            self.widget_ready = true;
        }
        return &self.widget;
    }
};

/// Render the media widget into a wlroots buffer. Caller destroys the
/// intermediate cairo surface.
pub fn renderToBuffer(
    widget: *media_mod.MediaWidget,
    style_: Style,
    width: i32,
    height: i32,
    scale: u32,
) ?*wlr.Buffer {
    const w_d: f64 = @floatFromInt(width * @as(i32, @intCast(scale)));
    const h_d: f64 = @floatFromInt(height * @as(i32, @intCast(scale)));
    const stride = cairo.cairo_format_stride_for_width(cairo.CAIRO_FORMAT_ARGB32, @intFromFloat(w_d));
    const surface = cairo.cairo_image_surface_create(cairo.CAIRO_FORMAT_ARGB32, @intFromFloat(w_d), @intFromFloat(h_d)) orelse return null;
    if (cairo.cairo_surface_status(surface) != cairo.CAIRO_STATUS_SUCCESS) {
        cairo.cairo_surface_destroy(surface);
        return null;
    }
    const cr = cairo.cairo_create(surface) orelse {
        cairo.cairo_surface_destroy(surface);
        return null;
    };
    defer cairo.cairo_destroy(cr);
    widget.renderCard(cr, w_d, h_d, style_, @floatFromInt(scale), null);
    cairo.cairo_surface_flush(surface);
    const data = cairo.cairo_image_surface_get_data(surface) orelse {
        cairo.cairo_surface_destroy(surface);
        return null;
    };
    const buf_size = @as(usize, @intCast(stride)) * @as(usize, @intFromFloat(h_d));
    // DataBuffer copies pixels, so the surface can be destroyed right after.
    const buf = DataBuffer.create(data[0..buf_size], @intFromFloat(w_d), @intFromFloat(h_d), stride) catch {
        cairo.cairo_surface_destroy(surface);
        return null;
    };
    cairo.cairo_surface_destroy(surface);
    return buf;
}

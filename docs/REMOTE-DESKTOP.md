# KidulWM-Aware Remote Desktop Strategy

When both the host and the client run KidulWM, they share a common visual language: the same 8%-94%-8% column layout, the same chamfer shader, the same window gaps, the same focus model, and the same widget SDK. This document describes how to exploit that homogeneity to minimise bandwidth and improve remote quality.

## 1. State That Can Be Rendered Client-Side

The client KidulWM instance can render everything that is structurallystatic or computable from a small model rather than an image:

| Visual element | Client-side action |
|----------------|--------------------|
| Window geometry / columns | Replicate layout engine from `LayoutUpdate` messages. |
| Z order / workspace matrix | Receive `WorkspaceState` deltas. |
| Window gaps | Read `gap` value and subtract locally. |
| Chamfered corners | Run the same GLSL/SDF corner shader using transmitted `corner_style`/`corner_depth`. |
| Focus ring / borders | Apply the same theme tokens and focus state locally. |
| Side-column opacity/scale | Apply the recede transform locally. |
| Cursor | Render cursor locally; only send small shape/hotspot updates. |
| Widget chrome / panels | Widgets already render themselves; client runs the same widget SDK and receives only data updates. |
| Animations (layout, focus zoom) | Run locally from `animation_key`/`duration`/`easing` parameters. |
| Empty desktop / wallpaper | Client owns it.Host only sends theme/wallpaper URI changes. |

The only content that must travel is the actual **surface texture** inside a window tile, because that is application output the client has no other way to reproduce.

## 2. State That Must Still Be Streamed

| Source | Why it must stream |
|--------|------------------|
| App window surfaces / GTK content | Arbitrary application pixels; cannot be reconstructed. |
| Video / hardware-decoding overlays | High pixel entropy; best streamed as H.264/AV1/HEVC encoded frames. |
| OpenGL/Vulkan / game frames | GPU-rendered content; capture via DMA-BUF or `wlr-screencopy`. |
| Cursor shape changes | Low-bandwidth; send cursor theme + name/hotspot, or small PNG atlas. |
| Fullscreen surfaces | Temporarily degenerate to stream the whole surface, since chrome is hidden. |

## 3. Damage Tracking at Window / Surface Level

Instead of full-frame encode, the host records damage per toplevel surface:

1. **Per-surface framebuffer.** Keep a host-side copy of the last-acknowledged surface contents by client.
2. **Compositor damage.** KidulWM already knows which surfaces changed from `wl_surface` damage/commit events. Re-use this signal.
3. **Window-level`Damage` message.** Send an ordered list of `{window_id, rects[], age}` deltas. If a window did not change, send no texture data for it; the client keeps its cached copy.
4. **Texture upload.** For damaged regions, stream compressed tiles (see below).
5. **Fallback full-frame.** If client cache is lost, the host can send a `KeyFrame` for that window only.
6. **Cursor delta.** Cursor position is sent as relative coordinates; shape changes are rare events.

## 4. Transport / Protocol

Recommendation: **custom KidulWM-aware protocol over QUIC**, with a control channel and per-surface data channels.

| Layer | Choice | Rationale |
|-------|--------|-----------|
| Transport | QUIC (RFC 9000) over UDP | Built-in TLS 1.3, 0-RTT, connection migration, independent streams, NAT traversal. |
| Signalling | One reliable bidirectional control stream | Auth, layout state, damage metadata, input events. |
| Media | Unordered datagrams + per-surface streams | Fits variable-window update model better than a single video stream. |
| codec per window | WebP/AVIF lossy tiles for static UI; h264/AV1 for video surfaces | UI tiles compress better than video codecs; video surfaces get traditional hardware encode. |
| Discovery | mDNS on LAN; static WireGuard endpoint over internet | Avoids exposing the host directly. |

Why not PipeWire/Sunshine/Moonlight as the primary stream? They stream full-frame video and know nothing about KidulWM’s layout. Keep them as **fallback capture paths** for opaque/fullscreen content, not as the main chrome-reduction mechanism.

Waypipe copies raw Wayland buffers and is unencrypted; it is unsuitable for untrusted networks and does not exploit shared chrome.

WebRTC DataChannel is an alternative, but its signalling complexity and browser assumptions add weight; QUIC is simpler for a KidulWM-only system.

## 5. Security & Authentication Model

Remote desktop connects a less trusted, often mobile client back to a high-value home AI PC. Proposed model:

1. **Network layer:** host listening only on a WireGuard interface or localhost + reverse tunnel. No open ports on the public internet.
2. **Device enrollment:** client generates an Ed25519 keypair; host stores authorised public keys in `~/.config/KidulWM/remote_keys/`. Pairing uses a short one-time code displayed/hosted in the settings tray.
3. **Session authentication:** FIDO2/WebAuthn or TOTP second factor per DESIGN-INPUTS.md. No password-only login.
4. **Capability grant:** host asks the local user to approve each connection and choose mode (`view-only`, `interactive`, `file-clip`).
5. **Seat containment:** remote session gets a dedicated `wl_seat`/pseudo-seat; it cannot inject input into the local session without explicit focus transfer.
6. **Clipboard gate:** clipboard transfers require a per-direction user approval and are logged.
7. **Audit log:** JSONL at `~/.local/state/KidulWM/remote-audit.logl` capturing connect, disconnect, auth method, capability changes, and clipboard/file events.
8. **Session timeout:** idle disconnect, screen-lock auto-disconnect, and rate limiting on auth attempts.

## 6. Implementation Phases

### Phase 0: Protocol sketch (1 week)
- Define protobuf/flatbuffers/JSON message schema for `Layout`, `Window`, `Damage`, `InputEvent`, `AuthChallenge`, `CapabilityGrant`.
- Pick QUIC library in Zig or a Rust bridge (`quinn`) if Zig maturity is lacking.

### Phase 1: Chrome-replication PoC (2-3 weeks)
- Run KidulWM host on one machine, client KidulWM on a second.
- Control stream only: host sends window geometry, focus, gaps, theme; client draws blank tiles with correct layout and chamfers.
- Verify layout sync, animations, and focus changes work with zero pixel streaming.

### Phase 2: Single-window surface diff (3-4 weeks)
- Capture one `xdg_surface` via `wlr-screencopy`.
- Compute per-window damage, encode changed tiles as WebP, send over QUIC datagram.
- Client composites tiles into its local window model.

### Phase 3: Multi-window / workspace model (3-4 weeks)
- Extend to all visible windows and side-column recedes.
- Add cursor relay and input event back-channel.
- Integrate video fallback: detect high-motion surfaces and switch to H.264/AV1 for that window.

### Phase 4: Security hardening (2-3 weeks)
- WireGuard/mDNS discovery, keypair enrollment, FIDO2/TOTP auth, audit logging, clipboard gates.
- Implement view-only/interactive modes and session containment.

### Phase 5: Daily-driver polish (ongoing)
- Adaptive bitrate, region-of-interest updates, predictive cursor, Vulkan/VA-API encode paths.
- Tablet/touch input mapping, stylus support, keyboard forwarding.

### Simplest Working PoC
Two KidulWM builds on the same LAN:
1. Host opens a QUIC listener on a hardcoded port; client connects and validates a pinned Ed25519 key.
2. Host sends a JSON `LayoutState` once per focus/layout change.
3. Client draws the layout with empty tiles, then receives one focused window’s surface tiles over QUIC and composites them.
4. Client mouse/keyboard events are sent back; host injects them into the local seat.

That proves the core claim: most of the screen can be reconstructed client-side, and only the application surface needs to travel.

## Unresolved Trade-offs

- **Shared renderer vs. duplicated shader code.** Keeping chamfer/gap/shadow rendering identical across Zig (host) and Zig or Rust (client) adds maintenance. Consider embedding the shaders as a single SPIR-V source of truth.
- **Replicating layout engine on client.** The layout algorithm becomes a wire protocol; changes must not silently desync. Host should send a `layout_protocol_version` and the client can reject unknown versions.
- **Per-window encoding vs. full-frame video.** Per-window is efficient for many small UI changes but harder to hardware-accelerate than a single NVENC frame. A hybrid approach (per-window tiles for UI, full-frame H.264 for fullscreen apps) is likely necessary.
- **WebRTC vs. QUIC.** WebRTC would reduce client-porting friction but couples us to browser-oriented APIs; QUIC keeps KidulWM-only purity but requires more client work.
